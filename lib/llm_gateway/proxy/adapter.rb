# frozen_string_literal: true

module LlmGateway
  module Proxy
    class Adapter
      attr_reader :client, :provider, :adapter_id

      def initialize(client, provider: "proxy", adapter_id: "proxy")
        @client = client
        @provider = provider.to_s
        @adapter_id = adapter_id.to_s
      end

      def stream(message, model: nil, tools: nil, system: nil, **options, &block)
        target_registration = target_registration()
        validate_model!(model, target_registration)
        target_adapter = LlmGateway.build_adapter(
          adapter: target_registration[:id],
          **client.target_config
        )
        mapper_class = target_adapter.stream_mapper_class
        raise LlmGateway::Errors::MissingMapperForProvider, "No stream_mapper configured" unless mapper_class

        compatibility = LlmGateway.models.compatibility_for(model, adapter: target_registration[:id])
        mapper = mapper_class.new(
          provider: target_registration[:provider],
          api: target_adapter.stream_api_name,
          model_definition: model
        )

        client.stream(
          normalize_messages(message),
          tools: tools,
          system: normalize_system(system),
          **options.merge(model: compatibility.provider_model_key)
        ) do |chunk|
          mapper.map(chunk, &block)
        end

        mapper.result
      end

      def validate_model!(model, registration = target_registration())
        if model.provider != registration[:provider]
          raise LlmGateway::Errors::ModelProviderMismatch,
            "Model provider #{model.provider.inspect} does not match proxy target provider #{registration[:provider].inspect}"
        end

        compatibility = LlmGateway.models.compatibility_for(model, adapter: registration[:id])
        unless compatibility
          raise LlmGateway::Errors::UnsupportedModelForAdapter,
            "Model #{model.provider}/#{model.id} is not supported by adapter #{registration[:id]}"
        end

        compatibility
      end

      private

      def target_registration
        LlmGateway::AdapterRegistry.fetch(client.target_provider)
      end

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
  end
end
