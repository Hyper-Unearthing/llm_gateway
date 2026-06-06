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
        options = options.merge(model: request[:model]) if request.key?(:model)
        adapter = build_adapter(request)

        body = Enumerator.new do |yielder|
          adapter.raw_stream(
            request[:messages],
            system: request[:system],
            tools: request[:tools],
            **options
          ) do |chunk|
            yielder << encode_sse(chunk)
          end
        end

        [ 200, { "content-type" => "text/event-stream", "cache-control" => "no-cache" }, body ]
      rescue KeyError, JSON::ParserError, ArgumentError => e
        json_error(400, e.message)
      rescue Errors::UnsupportedProvider => e
        json_error(404, e.message)
      rescue StandardError => e
        json_error(500, e.message)
      end

      private

      def build_adapter(request)
        provider = request.fetch(:provider)
        config = (request[:config] || {}).merge(provider: provider)

        LlmGateway.build_provider(config)
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
