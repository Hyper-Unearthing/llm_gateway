# frozen_string_literal: true

require "base64"
require_relative "message_mapper"

module LlmGateway
  module Adapters
    module OpenAi
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

        def self.map_response_format(response_format)
          response_format
        end

        def self.map_messages(messages)
          return messages unless messages

          # First map messages like Claude
          mapped_messages = messages.map do |msg|
            msg = msg.merge(role: "user") if msg[:role] == "developer"

            content = if msg[:content].is_a?(Array)
                msg[:content].map do |content|
                  MessageMapper.map_content(content)
                end
            else
              [ MessageMapper.map_content(msg[:content]) ]
            end

            {
              role: msg[:role],
              content: content
            }
          end
          # Then transform to OpenAI format
          mapped_messages.flat_map do |msg|
            # Handle array content with tool calls and tool results
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

        def self.map_system(system)
          if !system || system.empty?
            []
          else
            system.map do |msg|
              msg[:role] == "system" ? msg.merge(role: "developer") : msg
            end
          end
        end
      end
    end
  end
end
