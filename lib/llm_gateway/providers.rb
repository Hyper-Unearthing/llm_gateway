# frozen_string_literal: true

module LlmGateway
  module Providers
    # Returns an AdapterDefinition with the same construction/model validation
    # contract as built-in adapters. No endpoint is contacted during definition.
    def self.chat_completions(id:, base_endpoint:, option_mapper:, api_key: nil, system_role: "system")
      raise ArgumentError, "Provider id must not be empty" if id.to_s.strip.empty?
      raise ArgumentError, "option_mapper must respond to map" unless option_mapper.respond_to?(:map)
      unless %w[system developer].include?(system_role)
        raise ArgumentError, "system_role must be system or developer"
      end

      provider_id = id.to_s.dup.freeze
      role = system_role.dup.freeze
      client_defaults = { base_endpoint: base_endpoint.to_s.dup.freeze, api_key: api_key&.dup&.freeze }.freeze
      policy = option_mapper
      adapter_class = Class.new(Adapters::ChatCompletionsAdapter) do
        provider provider_id
        define_singleton_method(:system_role) { role }
        define_singleton_method(:option_mapper) { policy }
        define_singleton_method(:build) do |**config|
          super(**client_defaults.merge(config.transform_keys(&:to_sym)))
        end
      end
      adapter_class.definition
    end
  end
end
