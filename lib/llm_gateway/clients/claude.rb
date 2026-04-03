# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class Claude < BaseClient
      CLAUDE_CODE_VERSION = "2.1.2"

      def initialize(model_key: "claude-3-7-sonnet-20250219", api_key: ENV["ANTHROPIC_API_KEY"])
        @base_endpoint = "https://api.anthropic.com/v1"
        super(model_key: model_key, api_key: api_key)
      end

      def chat(messages, **kwargs)
        post("messages", build_body(messages, **kwargs))
      end

      def stream(messages, **kwargs, &block)
        post_stream("messages", build_body(messages, **kwargs), &block)
      end

      def get_oauth_access_token(access_token:, refresh_token:, expires_at:, &block)
        token_manager = LlmGateway::Clients::ClaudeCode::TokenManager.new(
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at
        )
        token_manager.on_token_refresh = block if block_given?
        token_manager.ensure_valid_token
        token_manager.access_token
      end

      def download_file(file_id)
        get("files/#{file_id}/content")
      end

      def upload_file(filename, content, mime_type = "application/octet-stream")
        post_file("files", content, filename, mime_type: mime_type)
      end

      private

      def build_body(messages, tools: nil, system: [], **options)
        body = {
          model: model_key,
          messages: messages
        }

        body.merge!(tools: tools) if LlmGateway::Utils.present?(tools)

        system = prepend_claude_code_identity(system) if claude_code_oauth_api_key?

        body.merge!(system: system) if LlmGateway::Utils.present?(system)
        body.merge!(options)
        body
      end

      def build_headers
        return claude_code_oauth_headers if claude_code_oauth_api_key?

        {
          "anthropic-version" => "2023-06-01",
          "content-type" => "application/json",
          "x-api-key" => api_key,
          "anthropic-beta" => "code-execution-2025-05-22,files-api-2025-04-14"
        }
      end

      def claude_code_oauth_api_key?
        api_key.to_s.start_with?("sk-ant-oat")
      end

      def claude_code_oauth_headers
        {
          "anthropic-version" => "2023-06-01",
          "content-type" => "application/json",
          "Authorization" => "Bearer #{api_key}",
          "anthropic-dangerous-direct-browser-access" => "true",
          "anthropic-beta" => "claude-code-20250219,oauth-2025-04-20",
          "user-agent" => "claude-cli/#{CLAUDE_CODE_VERSION} (external, cli)",
          "x-app" => "cli"
        }
      end

      def prepend_claude_code_identity(system)
        identity = {
          type: "text",
          text: "You are Claude Code, Anthropic's official CLI for Claude."
        }

        if system.nil? || system.empty?
          [ identity ]
        else
          [ identity ] + system
        end
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
