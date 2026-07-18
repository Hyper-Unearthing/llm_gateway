# frozen_string_literal: true

module LlmGateway
  module Models
    class Compatibility
      attr_reader :provider, :model_id, :adapter_id, :provider_model_key

      def initialize(provider:, model_id:, adapter_id:, provider_model_key: nil)
        @provider = provider.to_s.freeze
        @model_id = model_id.to_s.freeze
        @adapter_id = adapter_id.to_s.freeze
        @provider_model_key = (provider_model_key || model_id).to_s.freeze
        freeze
      end
    end
  end
end
