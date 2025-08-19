# frozen_string_literal: true

require "base64"

module LlmGateway
  module Adapters
    module OpenAi
      module Responses
        class BidirectionalMessageMapper < OpenAi::ChatCompletions::BidirectionalMessageMapper
          def map_content(content)
            # Convert string content to text format
            #

            content = { type: "text", text: content } unless content.is_a?(Hash)
            case content[:type]
            when "text"
              map_text_content(content)
            when "message"
              map_messages(content)
            when "output_text"
              map_output_text_content(content)
            when "tool_use"
              map_tool_use_content(content)
            when "function_call"
              map_tool_use_content(content)
            when "tool_result"
              map_tool_result_content(content)
            else
              content
            end
          end

        private

          def map_messages(message)
            message[:content].map { |content| map_content(content) }
          end

          def map_tool_result_content(content)
            {
              "type": "function_call_output",
              "call_id": content[:tool_use_id],
              "output": content[:content]
            }
          end

          def map_tool_use_content(content)
            if direction == LlmGateway::DIRECTION_OUT
              { id: content[:call_id], type: "tool_use", name: content[:name], input: parse_tool_arguments(content[:arguments]) }
            else
              { id: content[:id] }
            end
          end

          def map_output_text_content(content)
            {
              type: "text",
              text: content[:text]
            }
          end

          def map_text_content(content)
            {
              type: "input_text",
              text: content[:text]
            }
          end
        end
      end
    end
  end
end
