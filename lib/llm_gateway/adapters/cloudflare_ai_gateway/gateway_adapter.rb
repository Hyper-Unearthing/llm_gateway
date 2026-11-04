# frozen_string_literal: true

require_relative "../anthropic/messages_adapter"
require_relative "../chat_completions_adapter"
require_relative "routes"
require_relative "option_mapper"
require_relative "chat_option_mapper"
require_relative "stream_mapper"

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      class MessagesRouteAdapter < LlmGateway::Adapters::Anthropic::MessagesAdapter
        provider "cloudflare-ai-gateway"

        def self.provider_model_key(model) = Routes.for(model).model

        private

        def api_name = "gateway"
        def option_mapper = CloudflareAIGateway::OptionMapper
      end

      class CompletionsRouteAdapter < LlmGateway::Adapters::ChatCompletionsAdapter
        provider "cloudflare-ai-gateway"

        def self.system_role = "system"
        def self.option_mapper = CloudflareAIGateway::ChatOptionMapper

        private

        def api_name = "gateway"
      end

      # One public adapter/model namespace. Protocol selection is per request,
      # with no shared mutable route state, retries, or model substitutions.
      class GatewayAdapter < LlmGateway::Adapters::Adapter
        provider "cloudflare-ai-gateway"
        client_class LlmGateway::Clients::CloudflareAIGateway

        def raw_stream(message, model:, tools: nil, system: nil, **options, &block)
          model = resolve_model!(model)
          route = Routes.for(model)
          route_adapter = route.messages? ? MessagesRouteAdapter : CompletionsRouteAdapter
          route_adapter.new(client.for_route(route.transport)).raw_stream(
            message, model: model, tools: tools, system: system, **options, &block)
        rescue Errors::ClientError => error
          # Preserve error class/code and the upstream message, adding enough
          # context to diagnose a route without exposing credentials or URLs.
          raise error.exception("Cloudflare #{model.id} (#{route.transport}): #{error.message}")
        end

        private

        def api_name = "gateway"
        def stream_mapper = CloudflareAIGateway::StreamMapper
      end

      module Gateway
        extend DefinitionFacade
        define_adapter GatewayAdapter
      end

      # Preserve existing construction APIs; callers need not pick a protocol.
      ChatCompletionsAdapter = GatewayAdapter
      MessagesAdapter = GatewayAdapter
      ChatCompletions = Gateway
      Messages = Gateway
    end
  end
end
