# frozen_string_literal: true

module LlmGateway
  module Proxy
    class Adapter < LlmGateway::Adapters::Adapter
      provider "proxy"
      client_class LlmGateway::Proxy::Client

      def stream(message, model:, tools: nil, system: nil, **options, &block)
        target_adapter = client.adapter_class.build(**client.target_config)
        model = target_adapter.resolve_model!(model)
        mapper_class = target_adapter.stream_mapper_class
        raise LlmGateway::Errors::MissingMapperForProvider, "No stream_mapper configured" unless mapper_class

        mapper = mapper_class.new(
          provider: target_adapter.provider,
          api: target_adapter.stream_api_name,
          model_definition: model
        )

        client.stream(
          normalize_messages(message),
          tools: tools,
          system: normalize_system(system),
          **options.merge(model: target_adapter.class.provider_model_key(model))
        ) do |chunk|
          mapper.map(chunk, &block)
        end

        mapper.result
      end

      def resolve_model!(model)
        client.adapter_class.resolve_model!(model)
      end

      private

      def normalize_system(system)
        if system.nil?
          []
        elsif system.is_a?(String)
          [ { role: "system", content: system } ]
        elsif system.is_a?(Array)
          system
        else
          raise ArgumentError, "System parameter must be a string or array, got #{system.class}"
        end
      end

      def normalize_messages(message)
        message.is_a?(String) ? [ { role: "user", content: message } ] : message
      end
    end

    extend LlmGateway::Adapters::DefinitionFacade
    define_adapter Adapter
  end
end
