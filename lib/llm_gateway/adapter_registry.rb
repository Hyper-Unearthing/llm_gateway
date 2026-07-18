# frozen_string_literal: true

module LlmGateway
  class AdapterRegistry
    class << self
      def register(id, provider:, client:, adapter:)
        id = id.to_s
        raise ArgumentError, "Adapter id cannot be empty" if id.empty?

        registry[id] = {
          id: id.freeze,
          provider: provider.to_s.freeze,
          client: client,
          adapter: adapter
        }.freeze
      end

      def fetch(id)
        id = id.to_s
        registry.fetch(id) do
          raise Errors::UnsupportedProvider, "Unknown adapter: #{id}"
        end
      end
      alias resolve fetch

      def registered?(id)
        registry.key?(id.to_s)
      end

      def adapters
        registry.keys.freeze
      end

      def registration_for(adapter_class)
        registry.values.find { |registration| registration[:adapter] == adapter_class }
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
