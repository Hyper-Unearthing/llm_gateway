# frozen_string_literal: true

module LlmGateway
  module Adapters
    module AnthropicOptionMapper
      DEFAULT_MAX_TOKENS = 20_480
      REASONING_EFFORT_BUDGET_TOKENS = {
        "low" => 1024,
        "medium" => 5 * 1024,
        "high" => 10 * 1024,
        "xhigh" => 20 * 1024
      }.freeze

      module_function

      def map(options)
        mapped_options = options.reject { |key, _| %i[reasoning max_completion_tokens response_format prompt_cache_retention cache_key prompt_cache_key].include?(key) }
        mapped_options[:max_tokens] = options[:max_completion_tokens] || DEFAULT_MAX_TOKENS

        retention = options[:cache_retention]
        mapped_options[:cache_retention] = retention unless retention.nil?

        response_format = options[:response_format]
        mapped_options[:output_config] = normalize_output_config(response_format) unless response_format.nil?

        reasoning = options[:reasoning]
        return mapped_options if reasoning.nil? || reasoning.to_s == "none"

        mapped_options[:thinking] = normalize_reasoning(reasoning)
        mapped_options
      end

      def normalize_output_config(response_format)
        format_type = response_format.is_a?(Hash) ? response_format[:type] || response_format["type"] : response_format

        case format_type.to_s
        when "json_object", "json_schema"
          { format: "json_schema" }
        else
          { format: "text" }
        end
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
