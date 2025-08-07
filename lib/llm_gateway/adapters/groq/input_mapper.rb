# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Groq
      class InputMapper
        def self.map(data)
          {
            messages: map_messages(data[:messages]),
            response_format: map_response_format(data[:response_format]),
            tools: map_tools(data[:tools]),
            system: map_system(data[:system])
          }
        end

        private

        def self.map_system(system)
          system
        end

        def self.map_response_format(response_format)
          response_format
        end

        def self.map_messages(messages)
          return messages unless messages

          messages.flat_map do |msg|
            if msg[:content].is_a?(Array)
              # Handle array content with tool calls and tool results
              tool_calls = []
              regular_content = []
              tool_messages = []

              msg[:content].each do |content|
                case content[:type]
                when "tool_result"
                  tool_messages << map_tool_result_message(content)
                when "tool_use"
                  tool_calls << map_tool_usage(content)
                else
                  regular_content << content
                end
              end

              result = []

              # Add the main message with tool calls if any
              if tool_calls.any? || regular_content.any?
                main_msg = msg.dup
                main_msg[:role] = "assistant" if !main_msg[:role]
                main_msg[:tool_calls] = tool_calls if tool_calls.any?
                main_msg[:content] = regular_content.any? ? regular_content : nil
                result << main_msg
              end

              # Add separate tool result messages
              result += tool_messages

              result
            else
              # Regular message, return as-is
              [ msg ]
            end
          end
        end

        def self.map_tools(tools)
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

        def self.map_tool_usage(content)
            {
              'id': content[:id],
              'type': "function",
              'function': {
                'name': content[:name],
                'arguments': content[:input].to_json
              }
            }
        end

        def self.map_tool_result_message(content)
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
