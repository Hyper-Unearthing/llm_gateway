# frozen_string_literal: true

require "base64"
require_relative "bidirectional_message_mapper"

module LlmGateway
  module Adapters
    module OpenAi
      module Responses
        class InputMapper < OpenAi::ChatCompletions::InputMapper
          def self.message_mapper
            BidirectionalMessageMapper.new(LlmGateway::DIRECTION_IN)
          end

          def self.map_tools(tools)
            return tools unless tools

            tools.map do |tool|
              {
                type: "function",
                name: tool[:name],
                description: tool[:description],
                parameters: tool[:input_schema]
              }
            end
          end

          def self.map_messages(messages)
            return messages unless messages
            mapper = message_mapper

            # First map messages like Claude
            messages.map do |msg|
              if msg[:id]
                msg = msg.merge(role: "assistant")
                msg.slice(:id)
              else
                content = if msg[:content].is_a?(Array)
                    msg[:content].map do |content|
                      mapper.map_content(content)
                    end
                elsif msg[:id]
                  mapper.map_content(msg)
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
        end
      end
    end
  end
end
