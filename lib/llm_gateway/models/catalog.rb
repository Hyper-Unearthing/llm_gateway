# frozen_string_literal: true

module LlmGateway
  module Models
    class Catalog
      def initialize(definitions = [])
        @definitions = {}
        definitions.each { |definition| register_definition(definition) }
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

      private

      def register_definition(definition)
        key = [ definition.provider, definition.id ]
        raise ArgumentError, "Duplicate model catalog entry: #{key.join("/")}" if @definitions.key?(key)

        @definitions[key] = definition
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
