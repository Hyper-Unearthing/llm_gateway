# frozen_string_literal: true

require "base64"

module LlmGateway
  module Adapters
    module OpenAi
      class MessageMapper
        def self.map_content(content)
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

        def self.map_text_content(content)
          {
            type: "text",
            text: content[:text]
          }
        end

        def self.map_file_content(content)
          # Map text/plain to application/pdf for OpenAI
          media_type = content[:media_type] == "text/plain" ? "application/pdf" : content[:media_type]
          {
            type: "file",
            file: {
              filename: content[:name],
              file_data: "data:#{media_type};base64,#{Base64.encode64(content[:data])}"
            }
          }
        end

        def self.map_image_content(content)
          {
            type: "image_url",
            image_url: {
              url: "data:#{content[:media_type]};base64,#{content[:data]}"
            }
          }
        end

        def self.map_tool_use_content(content)
          {
            id: content[:id],
            type: "function",
            function: {
              name: content[:name],
              arguments: content[:input].to_json
            }
          }
        end

        def self.map_tool_result_content(content)
          {
            role: "tool",
            tool_call_id: content[:tool_use_id],
            content: content[:content]
          }
        end
      end
    end
  end
end
