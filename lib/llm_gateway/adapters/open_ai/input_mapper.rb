# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAi
      class InputMapper < LlmGateway::Adapters::Groq::InputMapper
        map :system do |_, value|
          if value.empty?
            []
          else
            value.map do |msg|
              msg[:role] == "system" ? msg.merge(role: "developer") : msg
            end
          end
        end
      end
    end
  end
end
