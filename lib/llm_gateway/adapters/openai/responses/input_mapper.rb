# frozen_string_literal: true

require "base64"
require_relative "bidirectional_message_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      module Responses
        class InputMapper < OpenAI::ChatCompletions::InputMapper
          def self.message_mapper
            BidirectionalMessageMapper.new(LlmGateway::DIRECTION_IN)
          end

          def self.map_tools(tools)
            return tools unless tools
            mapper = message_mapper

            tools.map do |tool|
              # Pass through provider-native/built-in tools (e.g. code_interpreter)
              # when no function name is provided.
              if tool[:name].nil? && tool["name"].nil?
                tool
              else
                mapped_tool = {
                  type: "function",
                  name: tool[:name],
                  description: tool[:description],
                  parameters: tool[:input_schema]
                }

                [ :contents, :content ].each do |key|
                  next unless tool[key].is_a?(Array)

                  mapped_tool[key] = tool[key].map do |entry|
                    entry.is_a?(Hash) ? mapper.map_content(entry.transform_keys(&:to_sym)) : entry
                  end
                end

                mapped_tool
              end
            end
          end

          def self.map_messages(messages)
            return messages unless messages
            mapper = message_mapper

            messages.flat_map do |msg|
              if msg[:id] && msg[:content].is_a?(Array)
                # Full AssistantMessage#to_h — expand content for stateless multi-turn
                map_assistant_history_message(msg)
              elsif msg[:id]
                # Bare item-reference (e.g. manually constructed { id: "item_xxx" })
                msg.slice(:id)
              else
                content = if msg[:content].is_a?(Array)
                    msg[:content].map do |content|
                      mapper.map_content(content)
                    end
                else
                  [ mapper.map_content(msg[:content]) ]
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

          # Map a full AssistantMessage#to_h into Responses API input items for
          # stateless multi-turn conversations.
          #
          #   text blocks   → { role: "assistant", content: [{ type: "output_text", ... }] }
          #   tool_use blocks → top-level function_call items
          #   server_tool_use blocks → provider-native built-in tool call items
          #   server_tool_result blocks → omitted (Responses stores built-in tool outputs)
          #   thinking blocks → omitted (model handles reasoning internally)
          def self.map_assistant_history_message(msg)
            blocks = (msg[:content] || []).map { |b| b.transform_keys(&:to_sym) }

            result = []

            blocks.each do |b|
              case b[:type]
              when "text"
                result << {
                  role: "assistant",
                  content: [ { type: "output_text", text: b[:text] } ]
                }
              when "tool_use"
                result << {
                  type: "function_call",
                  call_id: b[:id],
                  name: b[:name],
                  arguments: b[:input].is_a?(Hash) ? b[:input].to_json : (b[:input] || {}).to_json
                }
              when "server_tool_use"
                result << map_server_tool_use_history_item(b)
              end
            end

            result
          end

          def self.map_server_tool_use_history_item(block)
            input = block[:input].is_a?(Hash) ? block[:input] : {}

            {
              id: block[:id],
              type: block[:name],
              status: "completed"
            }.merge(input)
          end
        end
      end
    end
  end
end
