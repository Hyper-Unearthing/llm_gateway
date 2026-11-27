# frozen_string_literal: true

require "bigdecimal"

module LlmGateway
  module Models
    class CostCalculator
      TOKENS_PER_MILLION = BigDecimal("1000000")

      def self.calculate(definition, usage = nil, api: nil, **usage_buckets)
        new(definition, usage, api: api, **usage_buckets).calculate
      end

      def initialize(definition, usage = nil, api: nil, **usage_buckets)
        @pricing = definition&.pricing_for(api)
        @usage = usage.to_h.symbolize_keys.merge(usage_buckets)
      end

      def calculate
        return nil unless pricing

        rates = pricing.rates_for(input + cache_read + cache_write)
        components = {
          input: (rates.input * input) / TOKENS_PER_MILLION,
          output: (rates.output * output) / TOKENS_PER_MILLION,
          cache_read: (rates.cache_read * cache_read) / TOKENS_PER_MILLION,
          cache_write: (rates.cache_write * cache_write) / TOKENS_PER_MILLION
        }
        components[:total] = components.values.sum
        components.freeze
      end

      private

      attr_reader :pricing

      def input = count(:input)
      def output = count(:output)
      def cache_read = count(:cache_read)
      def cache_write = count(:cache_write)

      def count(key)
        Integer(@usage.fetch(key, 0))
      end
    end
  end
end
