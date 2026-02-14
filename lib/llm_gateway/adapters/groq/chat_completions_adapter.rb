# frozen_string_literal: true

require_relative "../adapter"
require_relative "input_mapper"
require_relative "output_mapper"

module LlmGateway
  module Adapters
    module Groq
      class ChatCompletionsAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: InputMapper,
            output_mapper: OutputMapper
          )
        end
      end
    end
  end
end
