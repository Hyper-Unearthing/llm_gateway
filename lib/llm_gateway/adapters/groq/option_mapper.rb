# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Groq
      module OptionMapper
        DEFAULT_TEMPERATURE = 0
        DEFAULT_MAX_COMPLETION_TOKENS = 20_480
        VALID_REASONING_LEVELS = %w[default low medium high].freeze

        # Source: https://console.groq.com/docs/text-chat.md and
        # https://console.groq.com/docs/api-reference.md#chat-create
        # API: Groq Chat Completions Create; accessed 2026-05-19.
        # Body parameters listed by the API reference: messages, model,
        # citation_options, compound_custom, disable_tool_validation, documents,
        # exclude_domains, frequency_penalty, function_call, functions,
        # include_domains, include_reasoning, logit_bias, logprobs,
        # max_completion_tokens, max_tokens, metadata, n, parallel_tool_calls,
        # presence_penalty, reasoning_effort, reasoning_format, response_format,
        # search_settings, seed, service_tier, stop, store, stream,
        # stream_options, temperature, tool_choice, tools, top_logprobs, top_p,
        # user.
        # This mapper intentionally excludes transcript/tool structural fields
        # (messages, tools) from option handling.
        VALID_OPTIONS = %i[
          model
          citation_options
          compound_custom
          disable_tool_validation
          documents
          exclude_domains
          frequency_penalty
          function_call
          functions
          include_domains
          include_reasoning
          logit_bias
          logprobs
          max_completion_tokens
          max_tokens
          metadata
          n
          parallel_tool_calls
          presence_penalty
          reasoning_effort
          reasoning_format
          response_format
          search_settings
          seed
          service_tier
          stop
          store
          stream
          stream_options
          temperature
          tool_choice
          top_logprobs
          top_p
          user
        ].freeze

        MANAGED_OPTIONS = %i[
          reasoning
          cache_key
          cache_retention
        ].freeze

        module_function

        def map(options)
          mapped_options = options.except(*MANAGED_OPTIONS)
          mapped_options[:temperature] = options.key?(:temperature) ? options[:temperature] : DEFAULT_TEMPERATURE
          mapped_options[:max_completion_tokens] = options[:max_completion_tokens] || DEFAULT_MAX_COMPLETION_TOKENS
          mapped_options[:response_format] = normalize_response_format(options[:response_format] || "text")

          reasoning = options[:reasoning]
          unless reasoning.nil? || reasoning.to_s == "none"
            mapped_options[:reasoning_effort] = normalize_reasoning_effort(reasoning)
            mapped_options[:reasoning_format] = "parsed"
          end

          validate_options!(mapped_options)
          mapped_options
        end

        def validate_options!(mapped_options)
          unknown_options = mapped_options.keys - VALID_OPTIONS
          return if unknown_options.empty?

          raise ArgumentError,
                "Unknown Groq Chat Completions options: #{unknown_options.join(', ')}. " \
                "Valid options: #{VALID_OPTIONS.join(', ')}."
        end

        def normalize_response_format(response_format)
          if response_format.is_a?(String)
            { type: response_format }
          else
            response_format
          end
        end

        def normalize_reasoning_effort(reasoning)
          effort = reasoning.to_s
          return effort if VALID_REASONING_LEVELS.include?(effort)

          raise ArgumentError, "Invalid reasoning '#{reasoning}'. Use 'none', 'default', 'low', 'medium', or 'high'."
        end
      end
    end
  end
end
