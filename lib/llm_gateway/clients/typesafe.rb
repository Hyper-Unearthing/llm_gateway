# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class TypeSafe < BaseClient
      def initialize(api_key: ENV["TYPESAFE_API_KEY"])
        @base_endpoint = "https://api.typesafe.ai/v1"
        super(api_key: api_key)
      end

      # https://docs.typesafe.ai/api
      def decisions(state:, questions:, model:)
        post("systemone", { model: model, state: state, questions: questions })
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
