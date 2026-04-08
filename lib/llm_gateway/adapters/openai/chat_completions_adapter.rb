# frozen_string_literal: true

require_relative "../adapter"
require_relative "chat_completions/input_mapper"
require_relative "chat_completions/input_message_sanitizer"
require_relative "chat_completions/output_mapper"
require_relative "chat_completions/option_mapper"
require_relative "file_output_mapper"
require_relative "chat_completions/stream_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      class ChatCompletionsAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: ChatCompletions::InputMapper,
            input_sanitizer: ChatCompletions::InputMessageSanitizer,
            output_mapper: ChatCompletions::OutputMapper,
            file_output_mapper: FileOutputMapper,
            option_mapper: ChatCompletions::OptionMapper,
            client_method: :chat,
            stream_mapper: ChatCompletions::StreamMapper
          )
        end
      end
    end
  end
end
