# frozen_string_literal: true

require_relative "anthropic"

module LlmGateway
  module Clients
    # Cloudflare-only credentials on nondeprecated REST/provider-native routes.
    # Route and wire model are selected by the adapter, never by this transport.
    class CloudflareAIGateway < Anthropic
      def initialize(account_id: ENV["CLOUDFLARE_ACCOUNT_ID"], gateway_id: ENV.fetch("CLOUDFLARE_GATEWAY_ID", "default"),
        api_key: ENV["CLOUDFLARE_AI_API_KEY"] || ENV["CLOUDFLARE_API_TOKEN"], route: :rest_completions)
        unless account_id.to_s.match?(/\A[0-9a-f]{32}\z/i)
          raise ArgumentError, "Cloudflare AI Gateway requires a 32-character hexadecimal account_id (CLOUDFLARE_ACCOUNT_ID)"
        end
        unless gateway_id.to_s.match?(/\A[A-Za-z0-9_-]{1,64}\z/)
          raise ArgumentError, "gateway_id must contain 1-64 letters, digits, underscores, or hyphens"
        end
        unless %i[rest_completions rest_messages anthropic_native].include?(route)
          raise ArgumentError, "Unknown Cloudflare route: #{route.inspect}"
        end

        super(api_key: api_key)
        @account_id, @gateway_id, @route = account_id, gateway_id, route
        @base_endpoint = if route == :anthropic_native
          "https://gateway.ai.cloudflare.com/v1/#{account_id}/#{gateway_id}/anthropic/v1"
        else
          "https://api.cloudflare.com/client/v4/accounts/#{account_id}/ai/v1"
        end
      end

      def for_route(route)
        self.class.new(account_id: @account_id, gateway_id: @gateway_id, api_key: api_key, route: route)
      end

      def chat(messages, **options)
        post(request_path, build_body(messages, **options))
      end

      def stream(messages, **options, &block)
        post_stream(request_path, build_body(messages, **options), &block)
      end

      private

      def request_path = @route == :rest_completions ? "chat/completions" : "messages"

      def build_headers
        headers = { "content-type" => "application/json" }
        if @route == :anthropic_native
          headers["cf-aig-authorization"] = "Bearer #{api_key}"
          headers["anthropic-version"] = "2023-06-01"
        else
          headers["Authorization"] = "Bearer #{api_key}"
          headers["cf-aig-gateway-id"] = @gateway_id
        end
        headers
      end

      # No provider defaults, OAuth identity/beta flags, or cache rewrites.
      def build_body(messages, model:, tools: nil, system: nil, **options)
        body = { model: model, messages: messages }
        body[:tools] = tools if tools.present?
        if @route == :rest_completions
          body[:messages] = Array(system) + messages
        elsif system.present?
          body[:system] = system
        end
        body.merge(options)
      end

      def handle_client_specific_errors(response, error)
        cloudflare_error = Array(error["errors"]).first
        error = error.merge(cloudflare_error) if cloudflare_error.is_a?(Hash)
        message = error["message"] || "Cloudflare request failed with HTTP #{response.code}"
        if Errors.context_overflow_message?(message)
          raise Errors::PromptTooLong.new(message, error["code"] || error["type"])
        end

        raise Errors::APIStatusError.new(message, error["code"] || error["type"])
      end
    end
  end
end
