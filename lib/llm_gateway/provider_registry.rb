# frozen_string_literal: true

module LlmGateway
  class ProviderRegistry
    class << self
      def register(name, client:, adapter:)
        registry[name.to_s] = { client: client, adapter: adapter }
      end

      def resolve(name)
        name = name.to_s
        entry = registry[name]
        raise Errors::UnsupportedProvider, "Unknown provider: #{name}" unless entry

        entry
      end

      def registered?(name)
        registry.key?(name.to_s)
      end

      def providers
        registry.keys
      end

      def reset!
        @registry = {}
      end

      private

      def registry
        @registry ||= {}
      end
    end
  end
end
