# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAI
      module ChatCompletions
        module OptionMapper
          DEFAULT_MAX_COMPLETION_TOKENS = 20_480
          SUPPORTED_REASONING_LEVELS = %w[minimal low medium high xhigh].freeze
          MODEL_REASONING_LEVELS = {
            # OpenAI docs note gpt-5.1 supports none/low/medium/high and
            # gpt-5-pro only supports high. "none" is handled by omitting the
            # managed reasoning field so existing behavior is preserved.
            /^gpt-5\.1(?:-|\z)/ => %w[low medium high],
            /^gpt-5-pro(?:-|\z)/ => %w[high]
          }.freeze

          # Source: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create/index.md
          # API: OpenAI Chat Completions Create; accessed 2026-05-18.
          # Body parameters listed by the API reference: messages, model, audio,
          # frequency_penalty, function_call, functions, logit_bias, logprobs,
          # max_completion_tokens, max_tokens, metadata, modalities, n,
          # parallel_tool_calls, prediction, presence_penalty, prompt_cache_key,
          # prompt_cache_retention, reasoning_effort, response_format,
          # safety_identifier, seed, service_tier, stop, store, stream,
          # stream_options, temperature, tool_choice, tools, top_logprobs, top_p,
          # user, verbosity, web_search_options.
          # This mapper intentionally excludes transcript/tool structural fields
          # (messages, tools) from option handling.

          VALID_OPTIONS = %i[
            model
            audio
            frequency_penalty
            function_call
            functions
            logit_bias
            logprobs
            max_completion_tokens
            max_tokens
            metadata
            modalities
            n
            parallel_tool_calls
            prediction
            presence_penalty
            prompt_cache_key
            prompt_cache_retention
            reasoning_effort
            response_format
            safety_identifier
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
            verbosity
            web_search_options
          ].freeze

          MANAGED_OPTIONS = %i[
            reasoning
            cache_key
            cache_retention
          ].freeze

          module_function

          def map(options)
            mapped_options = options.except(*MANAGED_OPTIONS)
            mapped_options[:max_completion_tokens] = options[:max_completion_tokens] || DEFAULT_MAX_COMPLETION_TOKENS

            cache_key = options[:cache_key]
            mapped_options[:prompt_cache_key] = cache_key unless cache_key.nil?

            cache_retention = options[:cache_retention]
            mapped_options[:prompt_cache_retention] = normalize_cache_retention(cache_retention) \
              unless cache_retention.nil?

            if mapped_options[:prompt_cache_key] && !mapped_options[:prompt_cache_retention]
              mapped_options[:prompt_cache_retention] = normalize_cache_retention("short")
            end

            if cache_retention.to_s == "none"
              mapped_options.delete(:prompt_cache_key)
              mapped_options.delete(:prompt_cache_retention)
            end

            reasoning = options[:reasoning]
            mapped_options[:reasoning_effort] = normalize_reasoning_effort(reasoning, model: options[:model]) \
              unless reasoning.nil? || reasoning.to_s == "none"

            validate_options!(mapped_options)
            mapped_options
          end

          def validate_options!(mapped_options)
            unknown_options = mapped_options.keys - VALID_OPTIONS
            return if unknown_options.empty?

            raise ArgumentError,
                  "Unknown OpenAI Chat Completions options: #{unknown_options.join(', ')}. " \
                  "Valid options: #{VALID_OPTIONS.join(', ')}."
          end

          def normalize_cache_retention(cache_retention)
            case cache_retention.to_s
            when "short"
              "in_memory"
            when "long"
              "24h"
            when "none"
              nil
            else
              raise ArgumentError,
                    "Invalid cache_retention '#{cache_retention}'. Use 'short', 'long', or 'none'."
            end
          end

          def normalize_reasoning_effort(reasoning, model: nil)
            ReasoningEffortMapper.closest_supported(reasoning, supported_reasoning_levels(model))
          end

          def supported_reasoning_levels(model)
            model_name = model.to_s
            matched_levels = MODEL_REASONING_LEVELS.find { |pattern, _levels| model_name.match?(pattern) }&.last
            matched_levels || SUPPORTED_REASONING_LEVELS
          end
        end
      end
    end
  end
end
