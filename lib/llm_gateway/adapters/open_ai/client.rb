# frozen_string_literal: true

require_relative "../../base_client"

module LlmGateway
  module Adapters
    module OpenAi
      class Client < BaseClient
        def initialize(model_key: "gpt-4o", api_key: ENV["OPENAI_API_KEY"])
          @base_endpoint = "https://api.openai.com/v1"
          super(model_key: model_key, api_key: api_key)
        end

        def chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096)
          body = {
            model: model_key,
            messages: system + messages,
            max_completion_tokens: max_completion_tokens
          }
          body[:tools] = tools if tools

          post("chat/completions", body)
        end


        def download_file(file_id)
          get("files/#{file_id}/content")
        end

        def generate_embeddings(input)
          body = {
            input:,
            model: model_key
          }
          post("embeddings", body)
        end

        def upload_file(filename, content, mime_type = "application/octet-stream", purpose: "user_data")
          post_file("files", content, filename, purpose: purpose, mime_type: mime_type)
        end

        private

        def build_headers
          {
            "content-type" => "application/json",
            "Authorization" => "Bearer #{api_key}"
          }
        end

        def handle_client_specific_errors(response, error)
          # OpenAI uses 'code' instead of 'type' for error codes
          error_code = error["code"]

          case response.code.to_i
          when 429
            raise Errors::RateLimitError.new(error["message"], error_code)
          when 503
            raise Errors::OverloadError.new(error["message"], error_code)
          end

          # If we get here, we didn't handle it specifically
          raise Errors::APIStatusError.new(error["message"], error_code)
        end
      end
    end
  end
end
