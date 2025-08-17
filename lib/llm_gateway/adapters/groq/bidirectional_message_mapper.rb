# frozen_string_literal: true

require_relative "../open_ai/bidirectional_message_mapper"

module LlmGateway
  module Adapters
    module Groq
      class BidirectionalMessageMapper < OpenAi::BidirectionalMessageMapper
        private

        def map_file_content(content)
          # Groq doesn't support files, return as text
          content[:text] || "[File: #{content[:name]}]"
        end
      end
    end
  end
end
