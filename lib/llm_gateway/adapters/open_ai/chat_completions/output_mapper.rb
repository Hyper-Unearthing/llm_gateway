# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAi
      module ChatCompletions
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
          message_mapper = BidirectionalMessageMapper.new(LlmGateway::DIRECTION_OUT)

          choices.map do |choice|
            message = choice[:message] || {}
            content_item = message_mapper.map_content(message[:content])
            tool_calls = message[:tool_calls] ? message[:tool_calls].map { |tool_call| message_mapper.map_content(tool_call) } : []

            # Only include content_item if it has actual text content
            content_array = []
            content_array << content_item if LlmGateway::Utils.present?(content_item[:text])
            content_array += tool_calls

            { content: content_array }
          end
        end
        end
      end
    end
  end
end
