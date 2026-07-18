# frozen_string_literal: true

require_relative "../adapter"
require_relative "acts_like_chat_completions"
require_relative "chat_completions/input_mapper"
require_relative "chat_completions/input_message_sanitizer"
require_relative "chat_completions/option_mapper"
require_relative "file_output_mapper"
require_relative "chat_completions/stream_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      class ChatCompletionsAdapter < Adapter
        provider "openai"
        client_class LlmGateway::Clients::OpenAI

        include ActsLikeOpenAIChatCompletions
      end

      ChatCompletions.extend(DefinitionFacade)
      ChatCompletions.define_adapter(ChatCompletionsAdapter)
    end
  end
end
