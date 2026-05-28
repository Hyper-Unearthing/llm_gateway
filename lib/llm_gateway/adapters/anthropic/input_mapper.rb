# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Anthropic
      class InputMapper
        def self.map(data)
          {
            messages: map_messages(data[:messages]),
            tools: data[:tools],
            system: map_system(data[:system])
          }
        end

        def self.map_content(content)
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
          when "server_tool_result"
            map_server_tool_result_content(content)
          when "thinking", "reasoning"
            map_reasoning_content(content)
          else
            content
          end
        end

        class << self
          private

          def map_messages(messages)
            return messages unless messages

            messages.map do |msg|
              msg = msg.merge(role: "user") if msg[:role] == "developer"

              content = if msg[:content].is_a?(Array)
                msg[:content].map { |content| map_content(content) }
              else
                [ map_content(msg[:content]) ]
              end

              {
                role: msg[:role],
                content: content
              }
            end
          end

          def map_system(system)
            if !system || system.empty?
              nil
            elsif system.length == 1 && system.first[:role] == "system"
              mapped = { type: "text", text: system.first[:content] }
              mapped[:cache_control] = system.first[:cache_control] if system.first[:cache_control]
              [ mapped ]
            else
              system
            end
          end

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
            mapped_content = content[:content]
            if mapped_content.is_a?(Array)
              mapped_content = mapped_content.map do |item|
                item.is_a?(Hash) ? map_content(item.transform_keys(&:to_sym)) : item
              end
            end

            {
              type: "tool_result",
              tool_use_id: content[:tool_use_id],
              content: mapped_content
            }
          end

          def map_server_tool_result_content(content)
            {
              type: native_server_tool_result_type(content),
              tool_use_id: content[:tool_use_id],
              content: content[:content]
            }
          end

          def native_server_tool_result_type(content)
            return content[:name] if content[:name] && content[:name] != "server_tool_result"

            result_type = content.dig(:content, :type)
            case result_type
            when "bash_code_execution_result"
              "bash_code_execution_tool_result"
            when /^text_editor_code_execution_.*_result$/
              "text_editor_code_execution_tool_result"
            else
              content[:name] || "server_tool_result"
            end
          end

          def map_reasoning_content(content)
            result = {
              type: "thinking",
              thinking: content[:reasoning]
            }
            result[:signature] = content[:signature] unless content[:signature].nil?
            result
          end
        end
      end
    end
  end
end
