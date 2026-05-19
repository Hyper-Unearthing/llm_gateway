# frozen_string_literal: true

require_relative "../openai/chat_completions/input_mapper"

module LlmGateway
  module Adapters
    module Groq
      class InputMapper < OpenAI::ChatCompletions::InputMapper
        def self.map(data)
          mapped = super
          mapped.merge(messages: map_groq_messages(mapped[:messages]))
        end

        def self.map_groq_messages(messages)
          return messages unless messages.is_a?(Array)

          messages.map { |message| map_groq_message(message) }
        end

        def self.map_groq_message(message)
          return message unless message.is_a?(Hash) && message[:role] == "assistant"
          return message unless message[:content].is_a?(Array)

          reasoning_blocks, content_blocks = message[:content].partition do |block|
            block.is_a?(Hash) && %w[reasoning thinking].include?(block[:type] || block["type"])
          end

          return message if reasoning_blocks.empty?

          mapped = message.merge(content: content_blocks.empty? ? nil : content_blocks)
          reasoning = reasoning_blocks.filter_map { |block| reasoning_text(block) }.join("\n")
          mapped[:reasoning] = reasoning unless reasoning.empty?
          mapped
        end

        def self.reasoning_text(block)
          block[:reasoning] || block["reasoning"] || block[:thinking] || block["thinking"]
        end

        private_class_method :map_groq_messages, :map_groq_message, :reasoning_text
      end
    end
  end
end
