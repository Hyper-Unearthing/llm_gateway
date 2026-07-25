# frozen_string_literal: true

require "bigdecimal"
require "date"

module LlmGateway
  module Models
    class Definition
      REASONING_LEVELS = %i[minimal low medium high max].freeze
      REASONING_BLOCK_SIZE = 1_024
      DEFAULT_REASONING_BUDGET_CEILING = 20_480

      attr_reader :provider, :id, :name, :source, :release_date, :last_updated,
                  :context_window, :max_output_tokens, :input_modalities, :output_modalities,
                  :capabilities, :reasoning_controls, :pricing

      def initialize(provider:, id:, name: nil, source: nil, release_date: nil, last_updated: nil,
                     context_window: nil, max_output_tokens: nil, input_modalities: [], output_modalities: [],
                     capabilities: {}, reasoning_controls: nil, pricing: nil)
        @provider = non_empty_string(provider, :provider)
        @id = non_empty_string(id, :id)
        @name = (name || id).to_s.freeze
        @source = source&.to_sym
        @release_date = normalize_date(release_date, :release_date)
        @last_updated = normalize_date(last_updated, :last_updated)
        @context_window = non_negative_integer(context_window, :context_window)
        @max_output_tokens = non_negative_integer(max_output_tokens, :max_output_tokens)
        @input_modalities = normalize_modalities(input_modalities)
        @output_modalities = normalize_modalities(output_modalities)
        @capabilities = normalize_capabilities(capabilities)
        @reasoning_controls = normalize_reasoning_controls(reasoning_controls)
        @pricing = Pricing.new(pricing) if pricing
        freeze
      end

      # Returns true, false, or nil when support for the capability is unknown.
      def supports?(capability)
        capabilities[capability.to_sym]
      end

      def supports_reasoning?
        supports?(:reasoning)
      end

      def supports_input?(modality)
        input_modalities.include?(modality.to_sym)
      end

      def supports_output?(modality)
        output_modalities.include?(modality.to_sym)
      end

      # Canonical, UI-safe reasoning values supported by this definition.
      # Provider-native controls remain available through #reasoning_controls.
      def reasoning_options
        return [].freeze unless supports?(:reasoning) == true

        options = [ :default ]
        control = preferred_reasoning_control
        return options.freeze unless control

        case control[:type]
        when "effort"
          options << :none if control[:values].include?("none")
          options.concat(control[:values].filter_map { |value| canonical_positive_reasoning_value(value) })
        when "budget_tokens"
          options << :none
          options.concat(REASONING_LEVELS)
        when "toggle"
          options.concat(%i[none high])
        end

        options.uniq.freeze
      end

      # Resolves a canonical reasoning option into a model control. Budget controls
      # use the catalog model's output limit, or a conservative ceiling when absent.
      def reasoning_control_for(option)
        canonical = normalize_reasoning_option_name(option)
        raise ArgumentError, "Unsupported reasoning option #{option.inspect} for #{provider}/#{id}" unless reasoning_options.include?(canonical)

        return nil if canonical == :default
        return { type: :none }.freeze if canonical == :none

        control = preferred_reasoning_control
        case control[:type]
        when "effort"
          { type: :effort, value: effort_for(control, canonical) }.freeze
        when "budget_tokens"
          { type: :budget_tokens, value: budget_for(control, canonical) }.freeze
        when "toggle"
          { type: :toggle, value: true }.freeze
        end
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

      def normalize_date(value, name)
        return nil if value.nil?
        return value if value.is_a?(Date)
        raise ArgumentError, "#{name} must be an ISO-8601 date" unless value.is_a?(String)

        Date.iso8601(value)
      rescue Date::Error
        raise ArgumentError, "#{name} must be an ISO-8601 date"
      end

      def normalize_reasoning_option_name(option)
        normalized = option.to_sym
        normalized == :xhigh ? :max : normalized
      rescue NoMethodError
        raise ArgumentError, "Invalid reasoning option #{option.inspect}"
      end

      def canonical_positive_reasoning_value(value)
        return :max if value == "xhigh"

        normalized = value.to_sym
        normalized if REASONING_LEVELS.include?(normalized)
      end

      def positive_reasoning_value?(value)
        !canonical_positive_reasoning_value(value).nil?
      end

      def preferred_reasoning_control
        controls = reasoning_controls || []
        controls.find { |control| control[:type] == "effort" && control[:values].any? { |value| positive_reasoning_value?(value) } } ||
          controls.find { |control| control[:type] == "budget_tokens" } ||
          controls.find { |control| control[:type] == "toggle" } ||
          controls.find { |control| control[:type] == "effort" }
      end

      def effort_for(control, canonical)
        control[:values].find { |value| canonical_positive_reasoning_value(value) == canonical }
      end

      def budget_for(control, canonical)
        minimum = round_up_to_reasoning_block(control[:min] || REASONING_BLOCK_SIZE)
        maximum = [ control[:max] || DEFAULT_REASONING_BUDGET_CEILING, max_output_tokens || DEFAULT_REASONING_BUDGET_CEILING ].min
        maximum = round_down_to_reasoning_block(maximum)
        raise ArgumentError, "No valid reasoning budget for #{provider}/#{id}" if maximum < minimum

        minimum_blocks = minimum / REASONING_BLOCK_SIZE
        maximum_blocks = maximum / REASONING_BLOCK_SIZE
        level_index = REASONING_LEVELS.index(canonical)
        blocks = minimum_blocks + ((maximum_blocks - minimum_blocks) * level_index.to_f / (REASONING_LEVELS.length - 1)).round
        blocks * REASONING_BLOCK_SIZE
      end

      def round_up_to_reasoning_block(value)
        ((value + REASONING_BLOCK_SIZE - 1) / REASONING_BLOCK_SIZE) * REASONING_BLOCK_SIZE
      end

      def round_down_to_reasoning_block(value)
        (value / REASONING_BLOCK_SIZE) * REASONING_BLOCK_SIZE
      end

      def normalize_reasoning_controls(controls)
        return nil if controls.nil?
        raise ArgumentError, "reasoning_controls must be an array" unless controls.is_a?(Array)

        controls.map.with_index do |option, index|
          raise ArgumentError, "reasoning_controls[#{index}] must be an object" unless option.is_a?(Hash)

          normalize_reasoning_option(option, index)
        end.freeze
      end

      def normalize_reasoning_option(option, index)
        normalized = normalize_source_value(option)
        type = normalized[:type]
        unless type.is_a?(String) && !type.empty?
          raise ArgumentError, "reasoning_controls[#{index}].type must be a non-empty string"
        end

        case type
        when "effort"
          values = normalized[:values]
          unless values.is_a?(Array) && values.all? { |value| value.is_a?(String) }
            raise ArgumentError, "reasoning_controls[#{index}].values must contain strings"
          end
          normalized[:values] = values.uniq.freeze
        when "budget_tokens"
          %i[min max].each do |boundary|
            next unless normalized.key?(boundary) && !normalized[boundary].nil?

            normalized[boundary] = non_negative_integer(normalized[boundary], "reasoning_controls[#{index}].#{boundary}")
          end
          if normalized[:min] && normalized[:max] && normalized[:max] < normalized[:min]
            raise ArgumentError, "reasoning_controls[#{index}].max must not be below min"
          end
        end

        deep_freeze(normalized)
      end

      def normalize_source_value(value)
        case value
        when String, Numeric, TrueClass, FalseClass, NilClass then value
        when Array then value.map { |item| normalize_source_value(item) }
        when Hash
          value.each_with_object({}) do |(key, item), normalized|
            unless key.is_a?(String) || key.is_a?(Symbol)
              raise ArgumentError, "reasoning option keys must be strings"
            end

            normalized[key.to_sym] = normalize_source_value(item)
          end
        else
          raise ArgumentError, "reasoning option attributes must contain JSON values"
        end
      end

      def deep_freeze(value)
        case value
        when Hash then value.each { |key, item| deep_freeze(key); deep_freeze(item) }
        when Array then value.each { |item| deep_freeze(item) }
        end
        value.freeze
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
