# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Claude
      class StreamOutputMapper
        def initialize
          @id = nil
          @model = nil
          @stop_reason = nil
          @usage = {}
          @content = []
          @current_block_index = nil
        end

        # Process a raw SSE event, update accumulator, return normalized event or nil
        def map_event(sse_event)
          event_type = sse_event[:event]
          data = sse_event[:data]

          case event_type
          when "message_start"
            handle_message_start(data)
          when "content_block_start"
            handle_content_block_start(data)
          when "content_block_delta"
            handle_content_block_delta(data)
          when "content_block_stop"
            handle_content_block_stop(data)
          when "message_delta"
            handle_message_delta(data)
          when "message_stop", "ping"
            nil
          when "error"
            handle_error(data)
          else
            nil
          end
        end

        # Return accumulated response in the same shape as Claude's non-streaming API
        def to_message
          {
            id: @id,
            model: @model,
            stop_reason: @stop_reason,
            usage: @usage,
            content: @content.map { |block| finalize_block(block) }
          }
        end

        private

        def handle_message_start(data)
          message = data[:message] || data
          @id = message[:id]
          @model = message[:model]
          @usage = message[:usage] || {}
          nil
        end

        def handle_content_block_start(data)
          @current_block_index = data[:index]
          block = data[:content_block]

          case block[:type]
          when "text"
            @content[@current_block_index] = { type: "text", text: +"" }
          when "thinking"
            @content[@current_block_index] = { type: "thinking", thinking: +"", signature: nil }
          when "tool_use"
            @content[@current_block_index] = {
              type: "tool_use",
              id: block[:id],
              name: block[:name],
              input_json: +""
            }
          else
            @content[@current_block_index] = block.dup
          end
          nil
        end

        def handle_content_block_delta(data)
          index = data[:index]
          delta = data[:delta]

          case delta[:type]
          when "text_delta"
            @content[index][:text] << delta[:text]
            { type: :text_delta, text: delta[:text] }
          when "thinking_delta"
            @content[index][:thinking] << delta[:thinking]
            { type: :thinking_delta, thinking: delta[:thinking] }
          when "input_json_delta"
            @content[index][:input_json] << delta[:partial_json]
            nil
          when "signature_delta"
            @content[index][:signature] = (@content[index][:signature] || "") + delta[:signature]
            nil
          else
            nil
          end
        end

        def handle_content_block_stop(data)
          index = data[:index]
          block = @content[index]

          if block[:type] == "tool_use"
            input = block[:input_json].empty? ? {} : JSON.parse(block[:input_json])
            input = LlmGateway::Utils.deep_symbolize_keys(input)
            return { type: :tool_use, id: block[:id], name: block[:name], input: input }
          end

          nil
        end

        def handle_message_delta(data)
          delta = data[:delta] || {}
          @stop_reason = delta[:stop_reason] if delta[:stop_reason]
          if data[:usage]
            @usage = @usage.merge(data[:usage])
          end
          nil
        end

        def handle_error(data)
          error_type = data[:error]&.[](:type) || data[:type] || "unknown_error"
          error_message = data[:error]&.[](:message) || data[:message] || "Unknown streaming error"

          case error_type
          when "overloaded_error"
            raise LlmGateway::Errors::OverloadError.new(error_message, error_type)
          when "rate_limit_error"
            raise LlmGateway::Errors::RateLimitError.new(error_message, error_type)
          when "authentication_error"
            raise LlmGateway::Errors::AuthenticationError.new(error_message, error_type)
          else
            raise LlmGateway::Errors::APIStatusError.new(error_message, error_type)
          end
        end

        def finalize_block(block)
          case block[:type]
          when "tool_use"
            input = if block[:input_json]
              block[:input_json].empty? ? {} : LlmGateway::Utils.deep_symbolize_keys(JSON.parse(block[:input_json]))
            else
              block[:input] || {}
            end
            { type: "tool_use", id: block[:id], name: block[:name], input: input }
          when "thinking"
            result = { type: "thinking", thinking: block[:thinking] }
            result[:signature] = block[:signature] if block[:signature]
            result
          else
            block
          end
        end
      end
    end
  end
end
