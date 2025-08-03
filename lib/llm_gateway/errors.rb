# frozen_string_literal: true

module LlmGateway
  module Errors
    class BaseError < StandardError
      attr_reader :code

      def initialize(message = nil, code = nil)
        @code = code
        super(message)
      end
    end

    class BadRequestError < BaseError; end
    class AuthenticationError < BaseError; end
    class PermissionDeniedError < BaseError; end
    class NotFoundError < BaseError; end
    class ConflictError < BaseError; end
    class UnprocessableEntityError < BaseError; end
    class RateLimitError < BaseError; end
    class InternalServerError < BaseError; end
    class APIStatusError < BaseError; end
    class APITimeoutError < BaseError; end
    class APIConnectionError < BaseError; end
    class OverloadError < BaseError; end
    class UnknownError < BaseError; end
    class PromptTooLong < BadRequestError; end
    class UnsupportedModel < BaseError; end
  end
end
