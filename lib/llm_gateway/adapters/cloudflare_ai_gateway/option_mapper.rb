# frozen_string_literal: true

require_relative "../anthropic_option_mapper"

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      module OptionMapper
        # Source: https://developers.cloudflare.com/ai-gateway/usage/rest-api/
        # Schema: https://platform.claude.com/docs/en/api/messages/create.md
        # API: Cloudflare REST/provider-native Messages; accessed 2026-11-01.
        # Body fields: max_tokens, messages, model, cache_control, container,
        # inference_geo, metadata, output_config, service_tier, stop_sequences,
        # stream, system, temperature, thinking, tool_choice, tools, top_k, top_p.
        # Exclude transcript/tools/system/stream (owned by the adapter), and
        # Anthropic-only container/service-tier/geography features. Support
        # depends on the selected third-party model; never accept upstream apiKey.
        VALID_OPTIONS = %i[
          model max_tokens cache_control metadata output_config stop_sequences
          temperature thinking tool_choice top_k top_p
        ].freeze
        MANAGED_OPTIONS = %i[max_completion_tokens reasoning_control response_format].freeze

        module_function

        def map(options)
          mapped = options.except(*MANAGED_OPTIONS)
          if options.key?(:max_completion_tokens)
            raise ArgumentError, "Specify max_completion_tokens or max_tokens, not both" if options.key?(:max_tokens)

            mapped[:max_tokens] = options[:max_completion_tokens]
          end

          if options.key?(:response_format)
            mapped[:output_config] = (mapped[:output_config] || {}).merge(
              AnthropicOptionMapper.normalize_output_config(options[:response_format]))
          end
          AnthropicOptionMapper.apply_reasoning_control!(mapped, options[:reasoning_control])
          choice = mapped[:tool_choice]
          mapped[:tool_choice] = { type: choice } if %w[none auto].include?(choice)

          # Preserve upstream defaults. Messages requires a token limit, but
          # the caller chooses it rather than inheriting Anthropic's default.
          validate_options!(mapped)
          mapped
        end

        def validate_options!(mapped)
          unknown = mapped.keys - VALID_OPTIONS
          return if unknown.empty?

          raise ArgumentError,
            "Unknown Cloudflare AI Gateway Messages options: #{unknown.join(', ')}. Valid options: #{VALID_OPTIONS.join(', ')}"
        end
      end
    end
  end
end
