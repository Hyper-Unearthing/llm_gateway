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

    class PromptError < BaseError; end

    class HallucinationError < PromptError; end
    class UnknownModel < PromptError; end
    class InvalidResponseGrammar < PromptError; end
  end
end
