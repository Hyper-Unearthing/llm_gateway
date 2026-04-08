# frozen_string_literal: true

require_relative "../adapter"
require_relative "acts_like_chat_completions"
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
        include ActsLikeOpenAIChatCompletions
      end
    end
  end
end
