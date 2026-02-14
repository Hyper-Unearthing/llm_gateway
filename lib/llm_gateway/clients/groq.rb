# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class Groq < BaseClient
      def initialize(model_key: "openai/gpt-oss-20b", api_key: ENV["GROQ_API_KEY"])
        @base_endpoint = "https://api.groq.com/openai/v1"
        super(model_key: model_key, api_key: api_key)
      end

      def chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096)
        body = {
          model: model_key,
          messages: system + messages,
          temperature: 0,
          max_completion_tokens: max_completion_tokens,
          response_format: response_format,
          tools: tools
        }

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

        case response.code.to_i
        when 400
          if error["message"]&.match?(/reduce the length of the messages/i)
            raise Errors::PromptTooLong.new(error["message"], error["type"])
          end
        when 413
          if error["message"]&.start_with?("Request too large")
            raise Errors::PromptTooLong.new(error["message"], error["type"])
          end
        when 429
          raise Errors::RateLimitError.new(error["type"], error_code) if error_code == "rate_limit_exceeded"

          raise Errors::OverloadError.new(error["message"], error_code)
        end

        # If we get here, we didn't handle it specifically
        raise Errors::APIStatusError.new(error["message"], error_code)
      end
    end
  end
end
