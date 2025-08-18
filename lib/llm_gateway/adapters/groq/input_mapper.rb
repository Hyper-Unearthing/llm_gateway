# frozen_string_literal: true

require_relative "bidirectional_message_mapper"
require_relative "../open_ai/chat_completions/input_mapper"

module LlmGateway
  module Adapters
    module Groq
      class InputMapper < OpenAi::ChatCompletions::InputMapper
        private

        def self.map_system(system)
          system
        end
      end
    end
  end
end
