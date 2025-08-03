# frozen_string_literal: true

module LlmGateway
  module Utils
    module_function

    def deep_symbolize_keys(hash)
      case hash
      when Hash
        hash.each_with_object({}) do |(key, value), result|
          result[key.to_sym] = deep_symbolize_keys(value)
        end
      when Array
        hash.map { |item| deep_symbolize_keys(item) }
      else
        hash
      end
    end

    def present?(value)
      !blank?(value)
    end

    def blank?(value)
      case value
      when nil
        true
      when String
        value.strip.empty?
      when Array, Hash
        value.empty?
      when Numeric
        false
      else
        value.respond_to?(:empty?) ? value.empty? : false
      end
    end
  end
end
