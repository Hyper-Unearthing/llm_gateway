# frozen_string_literal: true

require_relative "../adapter"
require_relative "../openai/acts_like_responses"
require_relative "../openai/responses/output_mapper"
require_relative "option_mapper"
require_relative "../openai/responses/stream_mapper"
require_relative "../openai/file_output_mapper"
require_relative "input_mapper"
require_relative "../input_message_sanitizer"

module LlmGateway
  module Adapters
    module OpenAICodex
      class ResponsesAdapter < Adapter
        include ActsLikeOpenAIResponses

        private

        def input_mapper
          OpenAICodex::InputMapper
        end

        def option_mapper
          OptionMapper
        end

        def perform_chat(messages, tools:, system:, **options)
          client.chat_codex(messages, tools: tools, system: system, **options)
        end

        def perform_stream(messages, tools:, system:, **options, &block)
          client.stream_codex(messages, tools: tools, system: system, **options, &block)
        end
      end
    end
  end
end
