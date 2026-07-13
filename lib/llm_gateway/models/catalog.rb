# frozen_string_literal: true

module LlmGateway
  module Models
    class Catalog
      def initialize(definitions = [], compatibilities = [])
        @definitions = {}
        @compatibilities = {}
        definitions.each { |definition| register_definition(definition) }
        compatibilities.each { |compatibility| register_compatibility(compatibility) }
      end

      def find(reference = nil, provider: nil, id: nil)
        provider, id = lookup_key(reference, provider:, id:)
        @definitions[[ provider, id ]]
      end

      def fetch(reference = nil, provider: nil, id: nil)
        provider, id = lookup_key(reference, provider:, id:)
        @definitions.fetch([ provider, id ]) do
          raise KeyError, "Unknown model catalog entry: #{provider}/#{id}"
        end
      end

      def all(provider: nil)
        return @definitions.values.freeze unless provider

        @definitions.select { |(definition_provider, _), _| definition_provider == provider.to_s }.values.freeze
      end

      def compatibility_for(model, adapter:)
        return nil unless model.is_a?(Definition)

        @compatibilities[[ model.provider, model.id, adapter.to_s ]]
      end

      def supported_by?(model, adapter:)
        !compatibility_for(model, adapter: adapter).nil?
      end

      def validate_compatibility!(model, provider:, adapter:)
        unless model.is_a?(Definition)
          raise LlmGateway::Errors::InvalidModelDefinition,
            "model must be a LlmGateway::Models::Definition, got #{model.class}"
        end

        if model.provider != provider.to_s
          raise LlmGateway::Errors::ModelProviderMismatch,
            "Model provider #{model.provider.inspect} does not match adapter provider #{provider.inspect}"
        end

        return true if compatibility_for(model, adapter: adapter)

        raise LlmGateway::Errors::UnsupportedModelForAdapter,
          "Model #{model.provider}/#{model.id} is not supported by adapter #{adapter}"
      end

      def provider_model_key_for!(model, provider:, adapter:)
        validate_compatibility!(model, provider:, adapter:)
        compatibility_for(model, adapter: adapter).provider_model_key
      end

      # Resolves a provider model key received at a serialization boundary.
      def model_for_provider_model_key(provider:, adapter:, provider_model_key:)
        compatibility = @compatibilities.values.find do |entry|
          entry.provider == provider.to_s &&
            entry.adapter_id == adapter.to_s &&
            entry.provider_model_key == provider_model_key.to_s
        end
        compatibility && find(provider: compatibility.provider, id: compatibility.model_id)
      end

      private

      def register_definition(definition)
        unless definition.is_a?(Definition)
          raise TypeError, "Expected Models::Definition, got #{definition.class}"
        end

        key = [ definition.provider, definition.id ]
        raise ArgumentError, "Duplicate model catalog entry: #{key.join("/")}" if @definitions.key?(key)

        @definitions[key] = definition
      end

      def register_compatibility(compatibility)
        unless compatibility.is_a?(Compatibility)
          raise TypeError, "Expected Models::Compatibility, got #{compatibility.class}"
        end

        model_key = [ compatibility.provider, compatibility.model_id ]
        unless @definitions.key?(model_key)
          raise ArgumentError, "Compatibility refers to unknown model: #{model_key.join("/")}"
        end

        key = [ *model_key, compatibility.adapter_id ]
        raise ArgumentError, "Duplicate model compatibility: #{key.join("/")}" if @compatibilities.key?(key)

        @compatibilities[key] = compatibility
      end

      def lookup_key(reference, provider:, id:)
        if reference
          if provider || id
            raise ArgumentError, "Pass either a model reference or provider:/id:, not both"
          end
          parse(reference)
        else
          if provider.nil? || provider.to_s.empty? || id.nil? || id.to_s.empty?
            raise ArgumentError, "Both provider: and id: are required"
          end
          [ provider.to_s, id.to_s ]
        end
      end

      def parse(reference)
        provider, id = reference.to_s.split("/", 2)
        if provider.nil? || provider.empty? || id.nil? || id.empty?
          raise ArgumentError, "Model reference must be in provider/model form: #{reference.inspect}"
        end

        [ provider, id ]
      end
    end
  end
end
