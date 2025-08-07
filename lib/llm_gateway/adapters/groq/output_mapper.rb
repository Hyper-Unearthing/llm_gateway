# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Groq
      class OutputMapper
        def self.map(data)
          {
            id: data[:id],
            model: data[:model],
            usage: data[:usage],
            choices: map_choices(data[:choices])
          }
        end

        private

        def self.map_choices(choices)
          return [] unless choices

          choices.map do |choice|
            message = choice[:message] || {}
            content_item = map_content_item(message)
            tool_calls = map_tool_calls(message[:tool_calls])

            # Only include content_item if it has actual text content
            content_array = []
            content_array << content_item if LlmGateway::Utils.present?(content_item[:text])
            content_array += tool_calls

            { content: content_array }
          end
        end

        def self.map_content_item(message)
          {
            text: message[:content],
            type: "text"
          }
        end

        def self.map_tool_calls(tool_calls)
          return [] unless tool_calls

          tool_calls.map do |tool_call|
            {
              id: tool_call[:id],
              type: "tool_use",
              name: tool_call.dig(:function, :name),
              input: parse_tool_arguments(tool_call.dig(:function, :arguments))
            }
          end
        end

        def self.parse_tool_arguments(arguments)
          return arguments unless arguments.is_a?(String)
          JSON.parse(arguments, symbolize_names: true)
        end
      end
    end
  end
end
