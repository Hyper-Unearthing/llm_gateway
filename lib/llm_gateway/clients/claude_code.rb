# frozen_string_literal: true

require_relative "claude"
require_relative "claude_code/oauth_flow"
require_relative "claude_code/token_manager"

module LlmGateway
  module Clients
    class ClaudeCode < Claude
      CLAUDE_CODE_VERSION = "2.1.2"
      attr_reader :token_manager, :access_token

      def initialize(
        model_key: "claude-3-7-sonnet-20250219",
        access_token: nil,
        refresh_token: nil,
        expires_at: nil,
        client_id: OAuthFlow::CLIENT_ID,
        client_secret: nil
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

      def chat(messages, tools: nil, system: [], max_completion_tokens: 20480, **options)
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
        body.merge!(options)

        post_with_retry("messages", body)
      end

      def stream(messages, tools: nil, system: [], max_completion_tokens: 20480, thinking: {}, **options, &block)
        ensure_valid_token

        body = {
          model: model_key,
          max_tokens: max_completion_tokens,
          messages: messages
        }

        body.merge!(thinking: thinking) if LlmGateway::Utils.present?(thinking)
        body.merge!(tools: tools) if LlmGateway::Utils.present?(tools)

        system = prepend_claude_code_identity(system)
        body.merge!(system: system) if LlmGateway::Utils.present?(system)
        body.merge!(options)

        post_stream_with_retry("messages", body, &block)
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

      def post_stream_with_retry(url_part, body = nil, extra_headers = {}, &block)
        post_stream(url_part, body, extra_headers, &block)
      rescue Errors::AuthenticationError => e
        raise e unless @token_manager&.token_expired?

        @token_manager.refresh_access_token
        @access_token = @token_manager.access_token
        post_stream(url_part, body, extra_headers, &block)
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
