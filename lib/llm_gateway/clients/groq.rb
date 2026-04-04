# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class Groq < BaseClient
      def initialize(model_key: "openai/gpt-oss-20b", api_key: ENV["GROQ_API_KEY"])
        @base_endpoint = "https://api.groq.com/openai/v1"
        super(model_key: model_key, api_key: api_key)
      end

      def chat(messages, tools: nil, system: [], **options)
        body = {
          model: model_key,
          messages: system + messages,
          tools: tools
        }
        body.merge!(options)

        post("chat/completions", body)
      end

      private

      def build_headers
        {
          "content-type" => "application/json",
          "Authorization" => "Bearer #{api_key}"
        }
      end

      def handle_client_specific_errors(response, error)
        # Groq likely uses 'code' like OpenAI since it's OpenAI-compatible
        error_code = error["code"]
        error_message = error["message"]

        if Errors.context_overflow_message?(error_message)
          raise Errors::PromptTooLong.new(error_message, error["type"])
        end

        case response.code.to_i
        when 429
          raise Errors::RateLimitError.new(error["type"], error_code) if error_code == "rate_limit_exceeded"

          raise Errors::OverloadError.new(error_message, error_code)
        end

        # If we get here, we didn't handle it specifically
        raise Errors::APIStatusError.new(error_message, error_code)
      end
    end
  end
end
