# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAI
      module Responses
        module OptionMapper
          DEFAULT_MAX_OUTPUT_TOKENS = 20_480
          SUPPORTED_REASONING_LEVELS = %w[minimal low medium high xhigh].freeze
          MODEL_REASONING_LEVELS = {
            # OpenAI docs note gpt-5.1 supports none/low/medium/high and
            # gpt-5-pro only supports high. "none" is handled by omitting the
            # managed reasoning field so existing behavior is preserved.
            /^gpt-5\.1(?:-|\z)/ => %w[low medium high],
            /^gpt-5-pro(?:-|\z)/ => %w[high]
          }.freeze

          # Source: https://developers.openai.com/api/reference/resources/responses/methods/create/index.md
          # API: OpenAI Responses Create; accessed 2026-05-18.
          # Body parameters listed by the API reference: background,
          # context_management, conversation, include, input, instructions,
          # max_output_tokens, max_tool_calls, metadata, model,
          # parallel_tool_calls, previous_response_id, prompt, prompt_cache_key,
          # prompt_cache_retention, reasoning, safety_identifier, service_tier,
          # store, stream, stream_options, temperature, text, tool_choice, tools,
          # top_logprobs, top_p, truncation, user.
          # This mapper intentionally excludes transcript/tool/system structural
          # fields (input, instructions, tools) from option handling.
          VALID_OPTIONS = %i[
            background
            context_management
            conversation
            include
            max_output_tokens
            max_tool_calls
            metadata
            model
            parallel_tool_calls
            previous_response_id
            prompt
            prompt_cache_key
            prompt_cache_retention
            reasoning
            safety_identifier
            service_tier
            store
            stream
            stream_options
            temperature
            text
            tool_choice
            top_logprobs
            top_p
            truncation
            user
          ].freeze

          MANAGED_OPTIONS = %i[
            max_completion_tokens
            response_format
            cache_key
            cache_retention
          ].freeze

          module_function

          def map(options)
            mapped_options = options.except(*MANAGED_OPTIONS)
            mapped_options[:max_output_tokens] = options[:max_completion_tokens] || options[:max_output_tokens] || DEFAULT_MAX_OUTPUT_TOKENS

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

            response_format = options[:response_format]
            mapped_options[:text] = text_with_response_format(mapped_options[:text], response_format) unless response_format.nil?

            reasoning = mapped_options.delete(:reasoning)
            mapped_options[:reasoning] = normalize_reasoning(reasoning, model: options[:model]) \
              unless reasoning.nil? || reasoning.to_s == "none"

            validate_options!(mapped_options)
            mapped_options
          end

          def validate_options!(mapped_options)
            unknown_options = mapped_options.keys - VALID_OPTIONS
            return if unknown_options.empty?

            raise ArgumentError,
                  "Unknown OpenAI Responses options: #{unknown_options.join(', ')}. " \
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

          def normalize_reasoning(reasoning, model: nil)
            effort = ReasoningEffortMapper.closest_supported(reasoning, supported_reasoning_levels(model))
            { effort: effort, summary: "detailed" }
          end

          def supported_reasoning_levels(model)
            model_name = model.to_s
            matched_levels = MODEL_REASONING_LEVELS.find { |pattern, _levels| model_name.match?(pattern) }&.last
            matched_levels || SUPPORTED_REASONING_LEVELS
          end

          def text_with_response_format(text, response_format)
            text_options = text ? text.dup : {}
            text_options[:format] = response_format.is_a?(String) ? { type: response_format } : response_format
            text_options
          end
        end
      end
    end
  end
end
