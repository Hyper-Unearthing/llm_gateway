# frozen_string_literal: true

require_relative "adapter"
require_relative "openai/acts_like_chat_completions"

module LlmGateway
  module Adapters
    # Protocol implementation. Provider identity and option policy are bound by
    # Providers.chat_completions rather than inherited from OpenAI.
    class ChatCompletionsAdapter < Adapter
      client_class LlmGateway::Clients::ChatCompletions
      include ActsLikeOpenAIChatCompletions

      private

      def map_input(input)
        mapped = super
        mapped[:system] = Array(mapped[:system]).map do |message|
          message.merge(role: self.class.system_role)
        end
        mapped
      end

      def option_mapper = self.class.option_mapper
    end
  end
end
