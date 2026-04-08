# frozen_string_literal: true

require "base64"

module LlmGateway
  module Adapters
    module OpenAI
      module Responses
        class BidirectionalMessageMapper < OpenAI::ChatCompletions::BidirectionalMessageMapper
          def map_content(content)
            # Convert string content to text format
            #

            content = { type: "text", text: content } unless content.is_a?(Hash)
            case content[:type]
            when "text"
              map_text_content(content)
            when "image"
              map_image_content(content)
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
            when "reasoning"
              map_reasoning_content(content)
            else
              content
            end
          end

        private

          def map_messages(message)
            message[:content].map { |content| map_content(content) }
          end

          def map_tool_result_content(content)
            output = content[:content]
            if output.is_a?(Array)
              output = output.map do |item|
                if item.is_a?(Hash)
                  map_content(item.transform_keys(&:to_sym))
                else
                  item
                end
              end
            end

            {
              "type": "function_call_output",
              "call_id": content[:tool_use_id],
              "output": output
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
              type: direction == LlmGateway::DIRECTION_IN ? "input_text" : "text",
              text: content[:text]
            }
          end

          def map_reasoning_content(content)
            if direction == LlmGateway::DIRECTION_IN
              return { id: content[:id] } if content[:id]

              content
            else
              {
                type: "reasoning",
                reasoning: normalize_reasoning_text(content[:summary]),
                signature: content[:signature]
              }
            end
          end

          def map_image_content(content)
            {
              type: "input_image",
              image_url: "data:#{content[:media_type]};base64,#{content[:data]}"
            }
          end

          def map_text_content(content)
            {
              type: "input_text",
              text: content[:text]
            }
          end

          def normalize_reasoning_text(summary)
            return summary if summary.is_a?(String)
            return nil unless summary.is_a?(Array)
            return nil if summary.empty?

            summary.filter_map do |item|
              next item if item.is_a?(String)

              item[:text] || item[:summary_text] || item[:reasoning]
            end.join("\n")
          end
        end
      end
    end
  end
end
