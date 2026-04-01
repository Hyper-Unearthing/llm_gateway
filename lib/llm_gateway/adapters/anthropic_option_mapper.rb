# frozen_string_literal: true

module LlmGateway
  module Adapters
    module AnthropicOptionMapper
      REASONING_EFFORT_BUDGET_TOKENS = {
        "low" => 1024,
        "medium" => 5 * 1024,
        "high" => 10 * 1024,
        "xhigh" => 20 * 1024
      }.freeze

      module_function

      def map(options)
        return options unless options.key?(:reasoning)

        reasoning = options[:reasoning]
        mapped_options = options.reject { |key, _| key == :reasoning }
        return mapped_options if reasoning.nil? || reasoning.to_s == "none"

        mapped_options.merge(thinking: normalize_reasoning(reasoning))
      end

      def normalize_reasoning(reasoning)
        budget_tokens = REASONING_EFFORT_BUDGET_TOKENS[reasoning.to_s] ||
          raise(ArgumentError,
                "Invalid reasoning '#{reasoning}'. Use 'none', 'low', 'medium', 'high', or 'xhigh'.")

        { type: "enabled", budget_tokens: budget_tokens }
      end
    end
  end
end
