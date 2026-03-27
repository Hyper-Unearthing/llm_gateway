# frozen_string_literal: true

require_relative "open_ai"
require_relative "openai_codex/oauth_flow"
require_relative "openai_codex/token_manager"

module LlmGateway
  module Clients
    # OpenAI Codex OAuth client.
    #
    # Uses the ChatGPT backend Codex endpoint with OAuth bearer tokens
    # (ChatGPT Plus / Pro subscription) rather than standard OpenAI API keys.
    #
    # The Codex backend requires streaming mode for all requests; the non-block
    # +chat+ method streams internally and returns the completed response object.
    #
    # Usage (direct):
    #
    #   client = LlmGateway::Clients::OpenAiCodex.new(
    #     access_token:  "...",
    #     refresh_token: "...",
    #     expires_at:    Time.now + 3600,
    #     account_id:    "..."
    #   )
    #
    #   # Non-streaming
    #   response = client.chat([{ role: "user", content: "Hello" }])
    #
    #   # Streaming
    #   client.stream([{ role: "user", content: "Hello" }]) { |sse| puts sse.inspect }
    #
    # First-time OAuth login:
    #
    #   tokens = LlmGateway::Clients::OpenAiCodex::OAuthFlow.new.login
    #   # => { access_token:, refresh_token:, expires_at:, account_id: }
    #
    class OpenAiCodex < OpenAi
      CODEX_BASE_ENDPOINT = "https://chatgpt.com/backend-api/codex"

      attr_reader :token_manager, :account_id
      attr_accessor :prompt_cache_key

      def initialize(
        model_key: "gpt-4o",
        access_token: nil,
        refresh_token: nil,
        expires_at: nil,
        account_id: nil,
        client_id: OAuthFlow::CLIENT_ID,
        reasoning_effort: nil
      )
        @reasoning_effort = reasoning_effort

        if refresh_token
          @token_manager = TokenManager.new(
            access_token: access_token,
            refresh_token: refresh_token,
            expires_at: expires_at,
            account_id: account_id,
            client_id: client_id
          )
          # Eagerly fetch a token only when none was provided
          @token_manager.ensure_valid_token if access_token.nil?
          access_token = @token_manager.access_token
          @account_id  = @token_manager.account_id
        end

        @oauth_access_token = access_token
        @account_id         = account_id || @account_id

        # Pass the token as api_key to satisfy BaseClient; override the endpoint.
        super(model_key: model_key, api_key: access_token)
        @base_endpoint = CODEX_BASE_ENDPOINT
      end

      # Register a callback that fires whenever the access token is refreshed.
      # The callback receives (access_token, refresh_token, expires_at).
      def on_token_refresh=(callback)
        @token_manager&.on_token_refresh = callback
      end

      # Send a chat request to the Codex backend.
      #
      # Without a block the stream is consumed internally and the completed
      # response Hash is returned.  With a block, raw SSE event hashes are
      # yielded as they arrive.
      def chat(messages, response_format: { type: "text" }, tools: nil, system: [],
               max_completion_tokens: 4096, **_options, &block)
        ensure_valid_token

        body = build_codex_body(messages, system, tools, max_completion_tokens)

        if block_given?
          post_stream_with_retry("responses", body, &block)
        else
          # Codex requires streaming; accumulate and return the completed response.
          completed_response = nil
          post_stream_with_retry("responses", body) do |raw_sse|
            if raw_sse[:event] == "response.completed"
              completed_response = raw_sse.dig(:data, :response)
            end
          end
          completed_response
        end
      end

      # Streaming interface: yields raw SSE event hashes to the block.
      def stream(messages, response_format: { type: "text" }, tools: nil, system: [],
                 max_completion_tokens: 4096, thinking: {}, **_options, &block)
        ensure_valid_token
        body = build_codex_body(messages, system, tools, max_completion_tokens, thinking:)
        post_stream_with_retry("responses", body, &block)
      end

      private

      # ------------------------------------------------------------------
      # Token helpers
      # ------------------------------------------------------------------

      def ensure_valid_token
        return unless @token_manager

        @token_manager.ensure_valid_token
        @oauth_access_token = @token_manager.access_token
        @account_id         = @token_manager.account_id
      end

      def post_with_retry(url_part, body = nil, extra_headers = {})
        post(url_part, body, extra_headers)
      rescue Errors::AuthenticationError => e
        raise e unless @token_manager&.token_expired?

        @token_manager.refresh_access_token!
        @oauth_access_token = @token_manager.access_token
        post(url_part, body, extra_headers)
      end

      def post_stream_with_retry(url_part, body = nil, extra_headers = {}, &block)
        post_stream(url_part, body, extra_headers, &block)
      rescue Errors::AuthenticationError => e
        raise e unless @token_manager&.token_expired?

        @token_manager.refresh_access_token!
        @oauth_access_token = @token_manager.access_token
        post_stream(url_part, body, extra_headers, &block)
      end

      # ------------------------------------------------------------------
      # Body builder
      # ------------------------------------------------------------------

      def build_codex_body(messages, system, tools, max_completion_tokens, thinking: nil)
        instructions = Array(system).filter_map { |s|
          s.is_a?(Hash) ? s[:content] : s
        }.join("\n")
        instructions = "You are a helpful assistant." if instructions.empty?

        body = {
          model: model_key,
          instructions: instructions,
          input: messages,
          store: false,
          include: [ "reasoning.encrypted_content" ],
          stream: true
        }

        # max_output_tokens is not supported by the Codex backend endpoint.
        body[:prompt_cache_key]        = @prompt_cache_key     if @prompt_cache_key
        body[:prompt_cache_retention]  = "24h"                 if @prompt_cache_key
        body[:tools]                   = tools                 if tools

        # Resolve reasoning effort: constructor-level @reasoning_effort takes
        # precedence, then fall back to the per-call thinking: param.
        effort = @reasoning_effort || resolve_reasoning_effort(thinking)
        body[:reasoning] = { effort: effort, summary: "detailed" } if effort

        body
      end

      # Translate the generic thinking: param (string effort OR hash with :effort
      # key) into a plain effort string understood by the Codex backend.
      # Anthropic-style hashes (type: "enabled", budget_tokens: …) are ignored
      # because the Codex backend has no equivalent concept.
      def resolve_reasoning_effort(thinking)
        case thinking
        when String
          thinking
        when Hash
          thinking[:effort] || thinking["effort"]
        end
      end

      # ------------------------------------------------------------------
      # Headers
      # ------------------------------------------------------------------

      def build_headers
        headers = {
          "content-type" => "application/json",
          "Authorization" => "Bearer #{@oauth_access_token}",
          "OpenAI-Beta" => "responses=experimental"
        }
        headers["chatgpt-account-id"] = @account_id if @account_id
        headers
      end
    end
  end
end
