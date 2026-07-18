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
        @catalog ||= Catalog.new(definitions)
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

      def reset_catalog!
        @catalog = nil
      end

      private

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
