# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Claude
      class BidirectionalMessageMapper
        attr_reader :direction

        def initialize(direction)
          @direction = direction
        end

        def map_content(content)
          # Convert string content to text format
          content = { type: "text", text: content } unless content.is_a?(Hash)

          case content[:type]
          when "text"
            map_text_content(content)
          when "file"
            map_file_content(content)
          when "image"
            map_image_content(content)
          when "tool_use"
            map_tool_use_content(content)
          when "tool_result"
            map_tool_result_content(content)
          else
            content
          end
        end

        private

        def map_text_content(content)
          result = {
            type: "text",
            text: content[:text]
          }
          result[:cache_control] = content[:cache_control] if content[:cache_control]
          result
        end

        def map_file_content(content)
          {
            type: "document",
            source: {
              data: content[:data],
              type: "text",
              media_type: content[:media_type]
            }
          }
        end

        def map_image_content(content)
          {
            type: "image",
            source: {
              data: content[:data],
              type: "base64",
              media_type: content[:media_type]
            }
          }
        end

        def map_tool_use_content(content)
          {
            type: "tool_use",
            id: content[:id],
            name: content[:name],
            input: content[:input]
          }
        end

        def map_tool_result_content(content)
          {
            type: "tool_result",
            tool_use_id: content[:tool_use_id],
            content: content[:content]
          }
        end
      end
    end
  end
end
