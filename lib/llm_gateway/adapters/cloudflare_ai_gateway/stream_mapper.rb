# frozen_string_literal: true

require_relative "../anthropic/stream_mapper"
require_relative "../openai/responses/stream_mapper"
require_relative "../openai/chat_completions/stream_mapper"

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      # Request routing and response decoding are independent: REST routes can
      # emit upstream-native SSE. Unknown formats must not silently return nil.
      class StreamMapper < LlmGateway::Adapters::StreamMapper
        def map(chunk, &block)
          event = chunk[:event] || chunk.dig(:data, :type)
          return if event == "ping"

          if event == "error"
            raise_stream_error!(chunk[:data], overload_codes: [ "overloaded_error" ])
          end
          @delegate ||= mapper_for(chunk).new(provider: provider, api: api, model_definition: model_definition)
          chunk = chunk.merge(event: event) if event && !chunk[:event]
          # Anthropic sends input/cache counts at message_start and output
          # counts at message_delta. The shared mapper consumes usage on delta.
          if chunk[:event] == "message_start"
            @initial_usage = chunk.dig(:data, :message, :usage) || {}
          elsif chunk[:event] == "message_delta" && @initial_usage
            data = chunk[:data] || {}
            chunk = chunk.merge(data: data.merge(usage: @initial_usage.merge(data[:usage] || {})))
          end
          @delegate.map(chunk, &block)
        end

        def finish(&block)
          raise Errors::APIStatusError.new("Cloudflare returned no recognized stream events", nil) unless @delegate

          @delegate.finish(&block)
          unless @delegate.result
            raise Errors::APIStatusError.new("Cloudflare stream ended without a completed message", nil)
          end
        end

        def result
          @delegate&.result
        end

        private

        def mapper_for(chunk)
          event = chunk[:event] || chunk.dig(:data, :type)
          return OpenAI::Responses::StreamMapper if event.to_s.start_with?("response.")
          return OpenAI::ChatCompletions::StreamMapper if chunk[:data].is_a?(Hash) && chunk[:data].key?(:choices)

          return Anthropic::StreamMapper if event == "message_start"

          raise Errors::APIStatusError.new("Unrecognized Cloudflare stream format: #{event.inspect}", nil)
        end
      end
    end
  end
end
