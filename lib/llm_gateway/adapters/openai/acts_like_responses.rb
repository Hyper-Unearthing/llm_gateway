# frozen_string_literal: true

module LlmGateway
  module Adapters
    module ActsLikeOpenAIResponses
      private

      def api_name = "responses"

      def input_mapper = OpenAI::Responses::InputMapper

      def input_sanitizer = InputMessageSanitizer

      def output_mapper = OpenAI::Responses::OutputMapper

      def file_output_mapper = OpenAI::FileOutputMapper

      def option_mapper = OpenAI::Responses::OptionMapper

      def stream_mapper = OpenAI::Responses::StreamMapper

      def perform_chat(messages, tools:, system:, **options)
        client.responses(messages, tools: tools, system: system, **options)
      end

      def perform_stream(messages, tools:, system:, **options, &block)
        client.stream_responses(messages, tools: tools, system: system, **options, &block)
      end
    end
  end
end
