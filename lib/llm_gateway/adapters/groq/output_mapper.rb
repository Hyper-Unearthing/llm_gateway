# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Groq
      class OutputMapper
        extend LlmGateway::FluentMapper

        mapper :tool_call do
          map :id
          map :type do
            "tool_use" # Always return 'tool_use' regardless of input
          end
          map :name, from: "function.name"
          map :input, from: "function.arguments" do |_, value|
            parsed = value.is_a?(String) ? JSON.parse(value) : value
            parsed
          end
        end

        mapper :content_item do
          map :text, from: "content"
          map :type, default: "text"
        end

        map :id
        map :model
        map :usage
        map :choices, from: "choices" do |_, value|
          value.map do |choice|
            message = choice[:message] || {}
            content_item = map_single(message, with: :content_item, default: {})
            tool_calls = map_collection(message[:tool_calls], with: :tool_call, default: [])

            # Only include content_item if it has actual text content
            content_array = []
            content_array << content_item if LlmGateway::Utils.present?(content_item["text"])
            content_array += tool_calls

            { content: content_array }
          end
        end
      end
    end
  end
end
