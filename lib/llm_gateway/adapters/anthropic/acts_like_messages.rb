# frozen_string_literal: true

module LlmGateway
  module Adapters
    module ActsLikeAnthropicMessages
      private

      def api_name = "messages"

      def input_mapper = Anthropic::InputMapper

      def input_sanitizer = InputMessageSanitizer

      def output_mapper = Anthropic::OutputMapper

      def file_output_mapper = Anthropic::FileOutputMapper

      def option_mapper = AnthropicOptionMapper

      def stream_mapper = Anthropic::StreamMapper
    end
  end
end
