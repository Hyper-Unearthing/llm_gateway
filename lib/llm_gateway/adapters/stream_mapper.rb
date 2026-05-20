# frozen_string_literal: true

require_relative "normalized_stream_accumulator"

module LlmGateway
  module Adapters
    class StreamMapper
      def result
        accumulator.result
      end

      private

      def accumulator
        @accumulator ||= LlmGateway::Adapters::NormalizedStreamAccumulator.new
      end

      def push_patches(patches, &block)
        patches.each do |patch|
          accumulator.push(patch, &block)
        end

        nil
      end

      def raise_stream_error!(data, overload_codes: [])
        error = stream_error_payload(data)
        message = error[:message] || error["message"] || "Stream error"
        code = error[:code] || error["code"] || error[:type] || error["type"]

        if LlmGateway::Errors.context_overflow_message?(message)
          raise LlmGateway::Errors::PromptTooLong.new(message, code)
        end

        if Array(overload_codes).any? { |overload_code| overload_code.to_s == code.to_s }
          raise LlmGateway::Errors::OverloadError.new(message, code)
        end

        raise LlmGateway::Errors::APIStatusError.new(message, code)
      end

      def stream_error_payload(data)
        data ||= {}
        error = data[:error] || data["error"]

        error.is_a?(Hash) ? error : data
      end
    end
  end
end
