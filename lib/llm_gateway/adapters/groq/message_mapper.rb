# frozen_string_literal: true

require_relative "../open_ai/message_mapper"

module LlmGateway
  module Adapters
    module Groq
      class MessageMapper < OpenAi::MessageMapper
        private

        def self.map_file_content(content)
          # Groq doesn't support files, return as text
          content[:text] || "[File: #{content[:name]}]"
        end
      end
    end
  end
end
