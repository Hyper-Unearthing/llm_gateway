# frozen_string_literal: true

require "base64"

module LlmGateway
  module Adapters
    module OpenAI
      module Responses
        class InputMapper < OpenAI::ChatCompletions::InputMapper
          def self.map_content(content)
            content = { type: "text", text: content } unless content.is_a?(Hash)

            case content[:type]
            when "text"
              map_text_content(content)
            when "image"
              map_image_content(content)
            when "message"
              map_messages_content(content)
            when "output_text"
              map_output_text_content(content)
            when "tool_use", "function_call"
              map_tool_use_content(content)
            when "tool_result"
              map_tool_result_content(content)
            when "reasoning"
              map_reasoning_content(content)
            else
              content
            end
          end

          class << self
            private

            def map_tools(tools)
              return tools unless tools

              tools.map do |tool|
                mapped_tool = {
                  type: "function",
                  name: tool[:name],
                  description: tool[:description],
                  parameters: tool[:input_schema]
                }

                [ :contents, :content ].each do |key|
                  next unless tool[key].is_a?(Array)

                  mapped_tool[key] = tool[key].map do |entry|
                    entry.is_a?(Hash) ? map_content(entry.transform_keys(&:to_sym)) : entry
                  end
                end

                mapped_tool
              end
            end

            def map_messages(messages)
              return messages unless messages

              messages.flat_map do |msg|
                if msg[:id] && msg[:content].is_a?(Array)
                  map_assistant_history_message(msg)
                elsif msg[:id]
                  msg.slice(:id)
                else
                  content = if msg[:content].is_a?(Array)
                    msg[:content].map { |content| map_content(content) }
                  else
                    [ map_content(msg[:content]) ]
                  end
                  if msg.dig(:content).is_a?(Array) && msg.dig(:content, 0, :type) == "tool_result"
                    content
                  else
                    {
                      role: msg[:role],
                      content: content
                    }
                  end
                end
              end
            end

            def map_assistant_history_message(msg)
              blocks = (msg[:content] || []).map { |b| b.transform_keys(&:to_sym) }

              text_blocks = blocks.select { |b| b[:type] == "text" }
              tool_use_blocks = blocks.select { |b| b[:type] == "tool_use" }

              result = []

              if text_blocks.any?
                result << {
                  role: "assistant",
                  content: text_blocks.map { |b| { type: "output_text", text: b[:text] } }
                }
              end

              tool_use_blocks.each do |b|
                result << {
                  type: "function_call",
                  call_id: b[:id],
                  name: b[:name],
                  arguments: b[:input].is_a?(Hash) ? b[:input].to_json : (b[:input] || {}).to_json
                }
              end

              result
            end

            def map_messages_content(message)
              message[:content].map { |content| map_content(content) }
            end

            def map_tool_result_content(content)
              output = content[:content]
              if output.is_a?(Array)
                output = output.map do |item|
                  item.is_a?(Hash) ? map_content(item.transform_keys(&:to_sym)) : item
                end
              end

              {
                type: "function_call_output",
                call_id: content[:tool_use_id],
                output: output
              }
            end

            def map_tool_use_content(content)
              { id: content[:id] }
            end

            def map_output_text_content(content)
              {
                type: "input_text",
                text: content[:text]
              }
            end

            def map_reasoning_content(content)
              return { id: content[:id] } if content[:id]

              content
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
          end
        end
      end
    end
  end
end
