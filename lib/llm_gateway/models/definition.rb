# frozen_string_literal: true

require "bigdecimal"

module LlmGateway
  module Models
    class Definition
      attr_reader :provider, :id, :name, :source, :context_window, :max_output_tokens,
                  :input_modalities, :reasoning, :pricing

      def initialize(provider:, id:, name: nil, source: nil, context_window: nil,
                     max_output_tokens: nil, input_modalities: [], reasoning: false,
                     pricing: nil)
        @provider = provider.to_s.freeze
        @id = id.to_s.freeze
        @name = (name || id).to_s.freeze
        @source = source&.to_sym
        @context_window = context_window
        @max_output_tokens = max_output_tokens
        @input_modalities = Array(input_modalities).map(&:to_sym).freeze
        @reasoning = reasoning == true ? { supported: true }.freeze : (reasoning || false).freeze
        @pricing = Pricing.new(pricing) if pricing
        freeze
      end

      class Pricing
        attr_reader :input, :output, :cache_read, :cache_write, :tiers

        def initialize(attributes)
          attributes = attributes.to_h.transform_keys(&:to_sym)
          @input = decimal(attributes.fetch(:input))
          @output = decimal(attributes.fetch(:output))
          @cache_read = decimal(attributes.fetch(:cache_read, 0))
          @cache_write = decimal(attributes.fetch(:cache_write, 0))
          @tiers = Array(attributes[:tiers]).map { |tier| Tier.new(tier) }.freeze
          freeze
        end

        def rates_for(input_tokens)
          tiers.reduce(self) do |rates, tier|
            tier.input_tokens_above < input_tokens && tier.input_tokens_above > rates.threshold ? tier : rates
          end
        end

        def threshold
          -1
        end

        private

        def decimal(value)
          BigDecimal(value.to_s)
        end
      end

      class Tier < Pricing
        attr_reader :input_tokens_above

        def initialize(attributes)
          attributes = attributes.to_h.transform_keys(&:to_sym)
          @input_tokens_above = Integer(attributes.fetch(:input_tokens_above))
          super
        end

        def threshold
          input_tokens_above
        end
      end
    end
  end
end
