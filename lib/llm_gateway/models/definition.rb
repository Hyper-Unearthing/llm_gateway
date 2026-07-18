# frozen_string_literal: true

require "bigdecimal"

module LlmGateway
  module Models
    class Definition
      attr_reader :provider, :id, :name, :source, :context_window, :max_output_tokens,
                  :input_modalities, :output_modalities, :capabilities, :pricing

      def initialize(provider:, id:, name: nil, source: nil, context_window: nil,
                     max_output_tokens: nil, input_modalities: [], output_modalities: [],
                     capabilities: {}, pricing: nil)
        @provider = non_empty_string(provider, :provider)
        @id = non_empty_string(id, :id)
        @name = (name || id).to_s.freeze
        @source = source&.to_sym
        @context_window = non_negative_integer(context_window, :context_window)
        @max_output_tokens = non_negative_integer(max_output_tokens, :max_output_tokens)
        @input_modalities = normalize_modalities(input_modalities)
        @output_modalities = normalize_modalities(output_modalities)
        @capabilities = normalize_capabilities(capabilities)
        @pricing = Pricing.new(pricing) if pricing
        freeze
      end

      # Returns true, false, or nil when support for the capability is unknown.
      def supports?(capability)
        capabilities[capability.to_sym]
      end

      def supports_input?(modality)
        input_modalities.include?(modality.to_sym)
      end

      def supports_output?(modality)
        output_modalities.include?(modality.to_sym)
      end

      private

      def non_empty_string(value, name)
        normalized = value.to_s
        raise ArgumentError, "#{name} must not be empty" if normalized.strip.empty?

        normalized.freeze
      end

      def non_negative_integer(value, name)
        return nil if value.nil?

        normalized = Integer(value)
        if normalized.negative? || (value.is_a?(Numeric) && value != normalized)
          raise ArgumentError
        end

        normalized
      rescue TypeError, ArgumentError, RangeError
        raise ArgumentError, "#{name} must be a non-negative integer"
      end

      def normalize_modalities(modalities)
        Array(modalities).map(&:to_sym).uniq.freeze
      end

      def normalize_capabilities(capabilities)
        capabilities.to_h.each_with_object({}) do |(name, supported), normalized|
          unless supported.nil? || supported == true || supported == false
            raise ArgumentError, "Capability #{name.inspect} must be true, false, or nil"
          end

          normalized[name.to_sym] = supported
        end.freeze
      end

      public

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
          decimal = BigDecimal(value.to_s)
          raise ArgumentError, "Pricing rates must be finite and non-negative" unless decimal.finite? && !decimal.negative?

          decimal
        rescue TypeError, ArgumentError
          raise ArgumentError, "Pricing rates must be finite and non-negative"
        end

        def non_negative_integer(value, name)
          normalized = Integer(value)
          if normalized.negative? || (value.is_a?(Numeric) && value != normalized)
            raise ArgumentError
          end

          normalized
        rescue TypeError, ArgumentError, RangeError
          raise ArgumentError, "#{name} must be a non-negative integer"
        end
      end

      class Tier < Pricing
        attr_reader :input_tokens_above

        def initialize(attributes)
          attributes = attributes.to_h.transform_keys(&:to_sym)
          @input_tokens_above = non_negative_integer(
            attributes.fetch(:input_tokens_above),
            "Tier input_tokens_above"
          )

          super
        end

        def threshold
          input_tokens_above
        end
      end
    end
  end
end
