# frozen_string_literal: true

require_relative "chat_completions"

module LlmGateway
  module Clients
    # AI Gateway's unified Chat Completions endpoint. Only the Cloudflare token
    # is sent: upstream credentials must not override Unified Billing.
    class CloudflareAIGateway < ChatCompletions
      def initialize(account_id: ENV["CLOUDFLARE_ACCOUNT_ID"], gateway_id: ENV.fetch("CLOUDFLARE_GATEWAY_ID", "default"),
        api_key: ENV["CLOUDFLARE_AI_API_KEY"] || ENV["CLOUDFLARE_API_TOKEN"])
        unless account_id.to_s.match?(/\A[0-9a-f]{32}\z/i)
          raise ArgumentError, "Cloudflare AI Gateway requires a 32-character hexadecimal account_id (CLOUDFLARE_ACCOUNT_ID)"
        end
        unless gateway_id.to_s.match?(/\A[A-Za-z0-9_-]{1,64}\z/)
          raise ArgumentError, "gateway_id must contain 1-64 letters, digits, underscores, or hyphens"
        end

        super(base_endpoint: "https://gateway.ai.cloudflare.com/v1/#{account_id}/#{gateway_id}/compat", api_key: api_key)
      end

      private

      def build_headers
        {
          "content-type" => "application/json",
          "cf-aig-authorization" => "Bearer #{api_key}"
        }
      end

      def handle_client_specific_errors(response, error)
        cloudflare_error = Array(error["errors"]).first
        error = error.merge(cloudflare_error) if cloudflare_error.is_a?(Hash)
        super(response, error)
      end
    end
  end
end
