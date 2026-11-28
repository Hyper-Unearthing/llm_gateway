# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class Cloudflare < BaseClient
      attr_reader :account_id

      def initialize(api_key: ENV["CLOUDFLARE_API_TOKEN"], account_id: ENV["CLOUDFLARE_ACCOUNT_ID"])
        unless account_id.is_a?(String) && account_id.match?(/\A[a-zA-Z0-9_-]+\z/)
          raise ArgumentError, "A Cloudflare account_id is required"
        end

        @account_id = account_id
        @base_endpoint = "https://api.cloudflare.com/client/v4/accounts/#{account_id}/ai"
        super(api_key: api_key)
      end

      # https://developers.cloudflare.com/workers-ai/models/clef/
      def decisions(state:, questions:, model:)
        response = post("run/#{model}", { model: model.split("/").last, state: state, questions: questions })
        if response[:success] == false
          raise Errors::APIStatusError, "Cloudflare decision request failed: #{response[:errors].inspect}"
        end

        response.fetch(:result)
      end

      private

      def build_headers
        { "content-type" => "application/json", "Authorization" => "Bearer #{api_key}" }
      end

      def handle_client_specific_errors(response, error)
        raise Errors::APIStatusError.new(error["message"] || response.body, response.code.to_i)
      end
    end
  end
end
