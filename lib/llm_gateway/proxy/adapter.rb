# frozen_string_literal: true

module LlmGateway
  module Proxy
    class Adapter
      attr_reader :client, :provider_key

      def initialize(client, provider_key: nil)
        @client = client
        @provider_key = provider_key
      end

      def stream(message, tools: nil, system: nil, **options, &block)
        target_adapter = LlmGateway.build_provider(client.target_config.merge(provider: client.target_provider))
        mapper_class = target_adapter.stream_mapper_class
        raise LlmGateway::Errors::MissingMapperForProvider, "No stream_mapper configured" unless mapper_class

        mapper = mapper_class.new(
          provider: LlmGateway::Client.provider_id_from_client(target_adapter.client),
          api: target_adapter.stream_api_name
        )

        client.stream(normalize_messages(message), tools: tools, system: normalize_system(system), **options) do |chunk|
          mapper.map(chunk, &block)
        end

        mapper.result
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
  end
end
