# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    # Transport for the Chat Completions wire protocol, without provider defaults.
    class ChatCompletions < BaseClient
      def initialize(base_endpoint:, api_key: nil)
        uri = URI.parse(base_endpoint)
        unless %w[http https].include?(uri.scheme) && uri.host && !uri.userinfo && !uri.query && !uri.fragment
          raise ArgumentError, "base_endpoint must be an HTTP(S) URL without credentials, query, or fragment"
        end

        @base_endpoint = base_endpoint.sub(%r{/+\z}, "")
        super(api_key:)
      end

      def chat(messages, tools: nil, system: [], model:, **options)
        post("chat/completions", request_body(messages, tools, system, model, options))
      end

      def stream(messages, tools: nil, system: [], model:, **options, &block)
        post_stream("chat/completions", request_body(messages, tools, system, model, options), &block)
      end

      private

      def request_body(messages, tools, system, model, options)
        options.merge(model: model, messages: Array(system) + messages).tap do |body|
          body[:tools] = tools if tools
        end
      end

      def build_headers
        { "content-type" => "application/json" }.tap do |headers|
          headers["Authorization"] = "Bearer #{api_key}" unless api_key.to_s.empty?
        end
      end

      def handle_client_specific_errors(response, error)
        message = error["message"] || "Chat Completions request failed with status #{response.code}: #{response.body}"
        if Errors.context_overflow_message?(message)
          raise Errors::PromptTooLong.new(message, error["code"] || error["type"])
        end

        raise Errors::APIStatusError.new(message, error["code"] || error["type"])
      end
    end
  end
end
