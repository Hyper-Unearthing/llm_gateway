# frozen_string_literal: true

module LlmGateway
  module Errors
    class BaseError < StandardError; end

    class ClientError < BaseError
      attr_reader :code

      def initialize(message = nil, code = nil)
        @code = code
        super(message)
      end
    end

    class BadRequestError < ClientError; end
    class AuthenticationError < ClientError; end
    class PermissionDeniedError < ClientError; end
    class NotFoundError < ClientError; end
    class ConflictError < ClientError; end
    class UnprocessableEntityError < ClientError; end
    class RateLimitError < ClientError; end
    class InternalServerError < ClientError; end
    class APIStatusError < ClientError; end
    class APITimeoutError < ClientError; end
    class APIConnectionError < ClientError; end
    class OverloadError < ClientError; end
    class UnknownError < ClientError; end
    class PromptTooLong < BadRequestError; end
    class UnsupportedModel < ClientError; end
    class UnsupportedProvider < ClientError; end
    class MissingMapperForProvider < ClientError; end

    OVERFLOW_PATTERNS = [
      /prompt is too long/i, # Anthropic
      /exceeds the context window/i, # OpenAI
      /reduce the length of the messages/i, # Groq
      /maximum context length is \d+ tokens/i,
      /context[_ ]length[_ ]exceeded/i,
      /too many tokens/i,
      /token limit exceeded/i,
      /request too large.*tokens per min/i, # OpenAI TPM wording
      /input tokens per minute/i, # Anthropic TPM wording
      /reduce the prompt length/i,
      /input or output tokens must be reduced/i
    ].freeze

    def self.context_overflow_message?(message)
      text = message.to_s
      return false if text.empty?

      OVERFLOW_PATTERNS.any? { |pattern| pattern.match?(text) }
    end

    class PromptError < BaseError; end

    class HallucinationError < PromptError; end
    class UnknownModel < PromptError; end
    class InvalidResponseGrammar < PromptError; end
  end
end
