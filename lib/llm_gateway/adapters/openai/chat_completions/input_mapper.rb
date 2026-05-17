# frozen_string_literal: true

require "base64"

module LlmGateway
  module Adapters
    module OpenAI
      module ChatCompletions
        class InputMapper
          def self.map(data)
            {
              messages: map_messages(data[:messages]),
              tools: map_tools(data[:tools]),
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
            when "tool_use", "function"
              map_tool_use_content(content)
            when "tool_result"
              map_tool_result_content(content)
            else
              content
            end
          end

          class << self
            private

            def map_messages(messages)
              return messages unless messages

              mapped_messages = messages.map do |msg|
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

              mapped_messages.flat_map do |msg|
                tool_calls = []
                regular_content = []
                tool_messages = []
                msg[:content].each do |content|
                  case content[:type] || content[:role]
                  when "tool"
                    tool_messages << content
                  when "function"
                    tool_calls << content
                  else
                    regular_content << content
                  end
                end
                result = []

                if tool_calls.any? || regular_content.any?
                  main_msg = msg.dup
                  main_msg[:role] = "assistant" if !main_msg[:role]
                  main_msg[:tool_calls] = tool_calls if tool_calls.any?
                  main_msg[:content] = regular_content.any? ? regular_content : nil
                  result << main_msg
                end

                result + tool_messages
              end
            end

            def map_tools(tools)
              return tools unless tools

              tools.map do |tool|
                {
                  type: "function",
                  function: {
                    name: tool[:name],
                    description: tool[:description],
                    parameters: tool[:input_schema]
                  }
                }
              end
            end

            def map_system(system)
              if !system || system.empty?
                []
              else
                system.map do |msg|
                  msg[:role] == "system" ? msg.merge(role: "developer") : msg
                end
              end
            end

            def map_text_content(content)
              {
                type: "text",
                text: content[:text]
              }
            end

            def map_file_content(content)
              media_type = content[:media_type] == "text/plain" ? "application/pdf" : content[:media_type]
              {
                type: "file",
                file: {
                  filename: content[:name],
                  file_data: "data:#{media_type};base64,#{Base64.encode64(content[:data])}"
                }
              }
            end

            def map_image_content(content)
              {
                type: "image_url",
                image_url: {
                  url: "data:#{content[:media_type]};base64,#{content[:data]}"
                }
              }
            end

            def map_tool_use_content(content)
              {
                id: content[:id],
                type: "function",
                function: {
                  name: content[:name],
                  arguments: content[:input].to_json
                }
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
                role: "tool",
                tool_call_id: content[:tool_use_id],
                content: mapped_content
              }
            end
          end
        end
      end
    end
  end
end
