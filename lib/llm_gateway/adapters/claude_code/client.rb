# frozen_string_literal: true

require_relative "../claude/client"
require_relative "token_manager"

module LlmGateway
  module Adapters
    module ClaudeCode
      class Client < Claude::Client
        CLAUDE_CODE_VERSION = "2.1.2"
        attr_reader :token_manager, :access_token

        def initialize(
          model_key: "claude-3-7-sonnet-20250219",
          access_token: nil,
          refresh_token: nil,
          expires_at: nil,
          client_id: ENV["ANTHROPIC_CLIENT_ID"],
          client_secret: ENV["ANTHROPIC_CLIENT_SECRET"]
        )
          @base_endpoint = "https://api.anthropic.com/v1"

          if refresh_token
            @token_manager = TokenManager.new(
              access_token: access_token,
              refresh_token: refresh_token,
              expires_at: expires_at,
              client_id: client_id,
              client_secret: client_secret
            )
            @token_manager.ensure_valid_token if access_token.nil?
            access_token = @token_manager.access_token
          end

          # Extract actual model name from claude_code/ prefix
          actual_model_key = model_key.to_s.sub(/^claude_code\//, "")

          @access_token = access_token
          super(model_key: actual_model_key, api_key: access_token)
        end

        # Delegate token refresh callback to token_manager
        def on_token_refresh=(callback)
          @token_manager&.on_token_refresh = callback
        end

        def chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096)
          ensure_valid_token

          body = {
            model: model_key,
            max_tokens: max_completion_tokens,
            messages: messages
          }

          body.merge!(tools: tools) if LlmGateway::Utils.present?(tools)

          # Prepend mandatory system prompt for Claude Code
          system = prepend_claude_code_identity(system)

          body.merge!(system: system) if LlmGateway::Utils.present?(system)

          post_with_retry("messages", body)
        end

        private

        def ensure_valid_token
          return unless @token_manager

          @token_manager.ensure_valid_token
          @access_token = @token_manager.access_token
        end

        def post_with_retry(url_part, body = nil, extra_headers = {})
          post(url_part, body, extra_headers)
        rescue Errors::AuthenticationError => e
          raise e unless @token_manager&.token_expired?

          @token_manager.refresh_access_token
          @access_token = @token_manager.access_token
          post(url_part, body, extra_headers)
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

        def build_headers
          {
            "anthropic-version" => "2023-06-01",
            "content-type" => "application/json",
            "Authorization" => "Bearer #{access_token}",
            "anthropic-dangerous-direct-browser-access" => "true",
            "anthropic-beta" => "claude-code-20250219,oauth-2025-04-20",
            "user-agent" => "claude-cli/#{CLAUDE_CODE_VERSION} (external, cli)",
            "x-app" => "cli"
          }
        end
      end
    end
  end
end
