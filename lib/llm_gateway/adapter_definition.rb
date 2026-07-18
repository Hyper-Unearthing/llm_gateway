# frozen_string_literal: true

module LlmGateway
  # Public, immutable description of an adapter. Definitions are useful when an
  # application wants to pass an adapter choice around without using its string ID.
  class AdapterDefinition
    attr_reader :adapter_class, :provider, :client_class

    def initialize(adapter_class)
      @adapter_class = adapter_class
      @provider = adapter_class.provider
      @client_class = adapter_class.client_class
      freeze
    end

    def build(**config)
      adapter_class.build(**config)
    end
  end

  module Adapters
    # Adds the small public definition API to names such as
    # Adapters::OpenAI::Responses without exposing adapter construction details.
    module DefinitionFacade
      def define_adapter(adapter_class)
        raise ArgumentError, "Adapter definition already configured for #{self}" if @definition

        @definition = AdapterDefinition.new(adapter_class)
      end

      def definition
        @definition || raise("No adapter definition configured for #{self}")
      end

      def build(**config)
        definition.build(**config)
      end

      def adapter_class
        definition.adapter_class
      end

      def provider
        definition.provider
      end

      def supports_model?(model)
        adapter_class.supports_model?(model)
      end

      def provider_model_key(model)
        adapter_class.provider_model_key(model)
      end

      def model_for_provider_model_key(provider_model_key)
        adapter_class.model_for_provider_model_key(provider_model_key)
      end

      def resolve_model!(model)
        adapter_class.resolve_model!(model)
      end
    end
  end
end
