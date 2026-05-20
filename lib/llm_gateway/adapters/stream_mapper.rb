# frozen_string_literal: true

require_relative "stream_accumulator"
require_relative "structs"

module LlmGateway
  module Adapters
    class StreamMapper
      def result
        accumulator.result
      end

      private

      def emit(event, &block)
        Array(event).each do |single_event|
          accumulator.push(single_event, &block) if single_event
        end

        nil
      end

      def accumulator
        @accumulator ||= ::StreamAccumulator.new
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
