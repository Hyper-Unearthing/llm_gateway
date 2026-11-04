# frozen_string_literal: true

module LlmGateway
  module Adapters
    module ActsLikeOpenAIChatCompletions
      private
      def api_name = "completions"

      def input_mapper = OpenAI::ChatCompletions::InputMapper

      def input_sanitizer = OpenAI::ChatCompletions::InputMessageSanitizer

      def stream_mapper = OpenAI::ChatCompletions::StreamMapper
    end
  end
end
