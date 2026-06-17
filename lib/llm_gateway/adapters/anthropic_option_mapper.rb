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

      # Source: https://platform.claude.com/docs/en/api/messages/create.md
      # API: Anthropic Messages Create; accessed 2026-05-18.
      # Body parameters listed by the API reference: max_tokens, messages, model,
      # cache_control, container, inference_geo, metadata, output_config,
      # service_tier, stop_sequences, stream, system, temperature, thinking,
      # tool_choice, tools, top_k, top_p.
      # This mapper intentionally excludes transcript/tool/system structural fields
      # (messages, system, tool_choice, tools) from option handling.

      VALID_OPTIONS = %i[
        max_tokens
        model
        cache_control
        cache_retention
        container
        inference_geo
        metadata
        output_config
        service_tier
        stop_sequences
        stream
        temperature
        thinking
        top_k
        top_p
      ].freeze

      MANAGED_OPTIONS = %i[
        reasoning
        max_completion_tokens
        response_format
        cache_key
        prompt_cache_key
        prompt_cache_retention
      ].freeze

      module_function

      def map(options)
        mapped_options = options.except(*MANAGED_OPTIONS)
        mapped_options[:max_tokens] = options[:max_completion_tokens] || DEFAULT_MAX_TOKENS

        response_format = options[:response_format]
        mapped_options[:output_config] = normalize_output_config(response_format) unless response_format.nil?

        reasoning = options[:reasoning]
        mapped_options[:thinking] = normalize_reasoning(reasoning) unless reasoning.nil? || reasoning.to_s == "none"

        validate_options!(mapped_options)
        mapped_options
      end

      def validate_options!(mapped_options)
        unknown_options = mapped_options.keys - VALID_OPTIONS
        return if unknown_options.empty?

        raise ArgumentError,
              "Unknown Anthropic Messages options: #{unknown_options.join(', ')}. " \
              "Valid options: #{VALID_OPTIONS.join(', ')}."
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
