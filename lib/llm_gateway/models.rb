# frozen_string_literal: true

require "json"

require_relative "models/definition"
require_relative "models/catalog"
require_relative "models/cost_calculator"
require_relative "models/explicit"

module LlmGateway
  module Models
    class << self
      def catalog
        @catalog ||= begin
          result = Catalog.new(definitions)
          registered_definitions.each_value { |definition| result.register(definition, replace: true) }
          result
        end
      end

      def find(reference = nil, provider: nil, id: nil)
        catalog.find(reference, provider:, id:)
      end

      def fetch(reference = nil, provider: nil, id: nil)
        catalog.fetch(reference, provider:, id:)
      end

      def all(provider: nil)
        catalog.all(provider:)
      end

      def register(definition = nil, replace: false, **attributes)
        if definition && attributes.any?
          raise ArgumentError, "Pass either a model definition or definition attributes, not both"
        end

        definition ||= Definition.new(**{ source: :user }.merge(attributes))
        unless definition.is_a?(Definition)
          raise ArgumentError, "Expected a model definition, got #{definition.inspect}"
        end

        key = [ definition.provider, definition.id ]
        catalog.register(definition, replace:)
        registered_definitions[key] = definition
        definition
      end

      # Rebuilds generated and explicit entries while retaining user registrations.
      def reset_catalog!
        @catalog = nil
      end

      private

      def registered_definitions
        @registered_definitions ||= {}
      end

      def definitions
        generated_catalog.fetch(:definitions).map { |attributes| Definition.new(**attributes) } +
          Explicit::DEFINITIONS.map { |attributes| Definition.new(**attributes) }
      end

      def generated_catalog
        @generated_catalog ||= JSON.parse(File.read(generated_catalog_path), symbolize_names: true)
      end

      def generated_catalog_path
        File.join(__dir__, "models", "generated.json")
      end
    end
  end

  def self.models
    Models
  end
end
