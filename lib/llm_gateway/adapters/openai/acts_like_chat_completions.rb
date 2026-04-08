# frozen_string_literal: true

module LlmGateway
  module Adapters
    module ActsLikeOpenAIChatCompletions
      private
      def api_name = "completions"

      def input_mapper = OpenAI::ChatCompletions::InputMapper

      def input_sanitizer = OpenAI::ChatCompletions::InputMessageSanitizer

      def output_mapper = OpenAI::ChatCompletions::OutputMapper

      def file_output_mapper = OpenAI::FileOutputMapper

      def option_mapper = OpenAI::ChatCompletions::OptionMapper

      def stream_mapper = OpenAI::ChatCompletions::StreamMapper
    end
  end
end
