# frozen_string_literal: true

require "json"

module LlmGateway
  # An explicit provider-owned allowlist and defaults. For managed-option
  # translation, supply a custom object/module responding to #map instead.
  class ProviderOptions
    STRUCTURAL_OPTIONS = %i[model messages tools system stream].freeze

    def initialize(allowed:, defaults: {})
      @allowed = allowed.map(&:to_sym).freeze
      @defaults = JSON.parse(JSON.generate(defaults), symbolize_names: true)
      structural = (@allowed + @defaults.keys) & STRUCTURAL_OPTIONS
      raise ArgumentError, "Structural options cannot be configured: #{structural.join(', ')}" if structural.any?

      validate!(@defaults)
      @defaults = @defaults.to_json.freeze
      freeze
    end

    def map(options)
      options = options.dup
      model = options.delete(:model)
      validate!(options)
      JSON.parse(@defaults, symbolize_names: true).merge(options).merge(model: model)
    end

    private

    def validate!(options)
      unknown = options.keys - @allowed
      return if unknown.empty?

      raise ArgumentError,
        "Unsupported provider options: #{unknown.join(', ')}. Allowed options: #{@allowed.join(', ')}"
    end
  end
end
