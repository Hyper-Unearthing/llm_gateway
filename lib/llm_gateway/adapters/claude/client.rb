# frozen_string_literal: true

require_relative "../../base_client"

module LlmGateway
  module Adapters
    module Claude
      class Client < BaseClient
        def initialize(model_key: "claude-3-7-sonnet-20250219", api_key: ENV["ANTHROPIC_API_KEY"])
          @base_endpoint = "https://api.anthropic.com/v1"
          super(model_key: model_key, api_key: api_key)
        end

        def chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096)
          body = {
            model: model_key,
            max_tokens: max_completion_tokens,
            messages: messages
          }

          body.merge!(tools: tools) if LlmGateway::Utils.present?(tools)
          body.merge!(system: system) if LlmGateway::Utils.present?(system)

          post("messages", body)
        end

        def download_file(file_id)
          get("files/#{file_id}/content")
        end

        def upload_file(filename, content, mime_type = "application/octet-stream")
          post_file("files", content, filename, mime_type: mime_type)
        end

        private

        def build_headers
          {
            "anthropic-version" => "2023-06-01",
            "content-type" => "application/json",
            "x-api-key" => api_key,
            "anthropic-beta" => "code-execution-2025-05-22,files-api-2025-04-14"
          }
        end

        def handle_client_specific_errors(response, error)
          case response.code.to_i
          when 400
            if error["message"]&.start_with?("prompt is too long")
              raise Errors::PromptTooLong.new(error["message"], error["type"])
            end
          end

          # If we get here, we didn't handle it specifically
          raise Errors::APIStatusError.new(error["message"], error["type"])
        end
      end
    end
  end
end
