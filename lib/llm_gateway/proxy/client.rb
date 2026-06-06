# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module LlmGateway
  module Proxy
    class Client
      attr_reader :url, :target_provider, :target_config, :path

      def initialize(url:, target_provider:, target_config: {}, api_key: nil, path: "/agent/llm_proxy", **_options)
        @url = url.to_s.sub(%r{/+\z}, "")
        @target_provider = target_provider.to_s
        @target_config = (target_config || {}).transform_keys(&:to_sym)
        @api_key = api_key
        @path = path.to_s.start_with?("/") ? path.to_s : "/#{path}"
      end

      def stream(messages, tools: nil, system: nil, **options, &block)
        uri = URI("#{url}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.read_timeout = 480
        http.open_timeout = 10

        request = Net::HTTP::Post.new(uri)
        request["content-type"] = "application/json"
        request["accept"] = "text/event-stream"
        request["accept-encoding"] = "identity"
        request["authorization"] = "Bearer #{@api_key}" if @api_key
        request.body = {
          provider: target_provider,
          config: target_config,
          messages: messages,
          system: system,
          tools: tools,
          options: options
        }.to_json

        http.request(request) do |response|
          unless response.code.to_i == 200
            body = +""
            response.read_body { |chunk| body << chunk }
            raise Errors::APIStatusError.new("Proxy request failed with status #{response.code}: #{body}", nil)
          end

          parse_sse_stream(response, &block)
        end
      end

      private

      def parse_sse_stream(response)
        buffer = +""
        response.read_body do |chunk|
          buffer << chunk
          while (idx = buffer.index("\n\n"))
            raw_event = buffer.slice!(0, idx + 2)
            event_type = nil
            data_lines = []

            raw_event.each_line do |line|
              line = line.chomp
              event_type = line.sub(/^event:\s*/, "") if line.start_with?("event:")
              data_lines << line.sub(/^data:\s*/, "") if line.start_with?("data:")
            end

            next if data_lines.empty?

            data_str = data_lines.join("\n")
            next if data_str == "[DONE]"

            data = begin
              JSON.parse(data_str).deep_symbolize_keys
            rescue JSON::ParserError
              { raw: data_str }
            end
            yield({ event: event_type, data: data })
          end
        end
      end
    end
  end
end
