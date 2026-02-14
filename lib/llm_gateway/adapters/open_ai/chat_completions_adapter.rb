# frozen_string_literal: true

require_relative "../adapter"
require_relative "chat_completions/input_mapper"
require_relative "chat_completions/output_mapper"
require_relative "file_output_mapper"

module LlmGateway
  module Adapters
    module OpenAi
      class ChatCompletionsAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: ChatCompletions::InputMapper,
            output_mapper: ChatCompletions::OutputMapper,
            file_output_mapper: FileOutputMapper
          )
        end
      end
    end
  end
end
