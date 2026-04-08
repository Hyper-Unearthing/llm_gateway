# frozen_string_literal: true

require_relative "../adapter"
require_relative "../openai/acts_like_chat_completions"
require_relative "../input_message_sanitizer"
require_relative "../openai/chat_completions/input_mapper"
require_relative "option_mapper"

module LlmGateway
  module Adapters
    module Groq
      class ChatCompletionsAdapter < Adapter
        include ActsLikeOpenAIChatCompletions

        private

        def file_output_mapper = nil
        def stream_mapper = nil
        def option_mapper = Groq::OptionMapper

        def map_input(input)
          groq_safe_input = input.dup
          groq_safe_input[:messages] = Array(input[:messages]).map do |msg|
            next msg unless msg.is_a?(Hash) && msg[:content].is_a?(Array)

            rewritten_content = msg[:content].map do |block|
              next block unless block.is_a?(Hash) && block[:type] == "file"

              {
                type: "text",
                text: block[:text] || "[File: #{block[:name]}]"
              }
            end

            msg.merge(content: rewritten_content)
          end

          mapped = super(groq_safe_input)
          mapped[:system] = Array(mapped[:system]).map do |msg|
            msg[:role] == "developer" ? msg.merge(role: "system") : msg
          end
          mapped
        end
      end
    end
  end
end
