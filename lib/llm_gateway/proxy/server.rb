# frozen_string_literal: true

require "json"

module LlmGateway
  module Proxy
    class Server
      PATH = "/agent/llm_proxy"
      def call(env)
        return not_found unless env["REQUEST_METHOD"] == "POST" && env["PATH_INFO"] == PATH

        request = JSON.parse(env["rack.input"].read).deep_symbolize_keys
        options = request[:options] || {}
        provider_model_key = request.key?(:model) ? request[:model] : options.delete(:model)
        registration = registration_for(request.fetch(:provider))
        model = resolve_model!(registration, provider_model_key)
        adapter = build_adapter(request, registration)

        body = Enumerator.new do |yielder|
          adapter.raw_stream(
            request[:messages],
            model: model,
            system: request[:system],
            tools: request[:tools],
            **options
          ) do |chunk|
            yielder << encode_sse(chunk)
          end
        end

        [ 200, { "content-type" => "text/event-stream", "cache-control" => "no-cache" }, body ]
      rescue KeyError, JSON::ParserError, ArgumentError, Errors::InvalidModelDefinition => e
        json_error(400, e.message)
      rescue Errors::UnsupportedProvider, Errors::UnsupportedModelForAdapter => e
        json_error(404, e.message)
      rescue StandardError => e
        json_error(500, e.message)
      end

      private

      def registration_for(id)
        LlmGateway::AdapterRegistry.fetch(id)
      end

      def resolve_model!(registration, provider_model_key)
        raise ArgumentError, "Proxy request must include a model" if provider_model_key.nil?

        LlmGateway.models.catalog.model_for_provider_model_key(
          provider: registration[:provider],
          adapter: registration[:id],
          provider_model_key: provider_model_key
        ) || raise(KeyError, "Unknown model for #{registration[:id]}: #{provider_model_key}")
      end

      def build_adapter(request, registration)
        LlmGateway.build_adapter(
          adapter: registration[:id],
          **(request[:config] || {})
        )
      end

      def encode_sse(chunk)
        event = chunk[:event]
        data = chunk[:data]
        out = +""
        out << "event: #{event}\n" if event
        JSON.generate(data).each_line { |line| out << "data: #{line.chomp}\n" }
        out << "\n"
      end

      def json_error(status, message)
        [ status, { "content-type" => "application/json" }, [ { error: message }.to_json ] ]
      end

      def not_found
        [ 404, { "content-type" => "application/json" }, [ { error: "Not found" }.to_json ] ]
      end
    end
  end
end
