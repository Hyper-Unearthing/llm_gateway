# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Groq
      class InputMapper
        extend LlmGateway::FluentMapper

        map :system
        map :response_format

        mapper :tool_usage do
          map :role, default: "assistant"
          map :content do
            nil
          end
          map :tool_calls, from: :content do |_, value|
            value.map do |content|
              {
                'id': content[:id],
                'type': "function",
                'function': {
                  'name': content[:name],
                  'arguments': content[:input].to_json
                }
              }
            end
          end
        end

        mapper :tool_result_message do
          map :role, default: "tool"
          map :tool_call_id, from: "tool_use_id"
          map :content
        end

        map :messages do |_, value|
          value.map do |msg|
            if msg[:role] == "user"
              msg
            elsif msg[:content].is_a?(Array)
              results = []
              # Handle tool_use messages
              tool_uses = msg[:content].select { |c| c[:type] == "tool_use" }
              results << map_single(msg, with: :tool_usage) if tool_uses.any?
              # Handle tool_result messages
              tool_results = msg[:content].select { |c| c[:type] == "tool_result" }
              tool_results.each do |content|
                results << map_single(content, with: :tool_result_message)
              end

              results
            else
              msg
            end
          end.flatten
        end

        map :tools do |_, value|
          if value
            value.map do |tool|
              {
                type: "function",
                function: {
                  name: tool[:name],
                  description: tool[:description],
                  parameters: tool[:input_schema]
                }
              }
            end
          else
            value
          end
        end
      end
    end
  end
end
