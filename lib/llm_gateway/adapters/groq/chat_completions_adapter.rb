# frozen_string_literal: true

require_relative "../adapter"
require_relative "../input_message_sanitizer"
require_relative "input_mapper"
require_relative "output_mapper"
require_relative "option_mapper"

module LlmGateway
  module Adapters
    module Groq
      class ChatCompletionsAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: InputMapper,
            input_sanitizer: LlmGateway::Adapters::InputMessageSanitizer,
            output_mapper: OutputMapper,
            option_mapper: OptionMapper,
            client_method: :chat
          )
        end
      end
    end
  end
end
