# frozen_string_literal: true

require_relative "message_mapper"
require_relative "../open_ai/input_mapper"

module LlmGateway
  module Adapters
    module Groq
      class InputMapper < OpenAi::InputMapper
        private

        def self.map_system(system)
          system
        end
      end
    end
  end
end
