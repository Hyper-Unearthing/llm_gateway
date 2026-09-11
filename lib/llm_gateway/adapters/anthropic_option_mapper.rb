# frozen_string_literal: true

module LlmGateway
  module Adapters
    module AnthropicOptionMapper
      DEFAULT_MAX_TOKENS = 20_480
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
        reasoning_control
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
        unless response_format.nil?
          mapped_options[:output_config] = (mapped_options[:output_config] || {}).merge(normalize_output_config(response_format))
        end

        apply_reasoning_control!(mapped_options, options[:reasoning_control])

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
        when "json_schema"
          raise ArgumentError, "response_format json_schema requires a schema object" unless response_format.is_a?(Hash)

          definition = response_format[:json_schema] || response_format["json_schema"] || response_format
          schema = definition[:schema] || definition["schema"]
          raise ArgumentError, "response_format json_schema requires a schema object" unless schema.is_a?(Hash)

          { format: { type: "json_schema", schema: schema } }
        when "text"
          {}
        else
          raise ArgumentError, "Unsupported Anthropic response_format: #{format_type}"
        end
      end

      def apply_reasoning_control!(mapped_options, control)
        return if control.nil? || control[:type] == :none

        case control[:type]
        when :budget_tokens
          mapped_options[:thinking] = { type: "enabled", budget_tokens: control.fetch(:value) }
        when :effort
          mapped_options[:thinking] = { type: "adaptive" }
          mapped_options[:output_config] = (mapped_options[:output_config] || {}).merge(effort: control.fetch(:value))
        when :toggle
          mapped_options[:thinking] = { type: "adaptive" } if control[:value]
        else
          raise ArgumentError, "Unsupported Anthropic reasoning control: #{control.inspect}"
        end
      end
    end
  end
end
