# frozen_string_literal: true

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      module OptionMapper
        # Source: https://developers.cloudflare.com/ai-gateway/usage/chat-completion/
        # API: AI Gateway unified OpenAI-compatible Chat Completions; accessed 2026-10-31.
        # The endpoint documents model ({provider}/{model}) and upstream apiKey;
        # apiKey is deliberately excluded here to avoid overriding Unified Billing.
        # Generation fields follow the upstream Chat Completions contract:
        # https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create/index.md
        # That reference lists model, messages, audio, frequency_penalty,
        # function_call, functions, logit_bias, logprobs, max_completion_tokens,
        # max_tokens, metadata, modalities, n, parallel_tool_calls, prediction,
        # presence_penalty, prompt_cache_key, prompt_cache_retention,
        # reasoning_effort, response_format, safety_identifier, seed,
        # service_tier, stop, store, stream, stream_options, temperature,
        # tool_choice, tools, top_logprobs, top_p, user, verbosity,
        # web_search_options. This policy intentionally exposes only a common
        # generation subset. Actual support still depends on the upstream model.
        # Transcript/tools/stream and OpenAI-specific caching/storage are excluded.
        VALID_OPTIONS = %i[
          model max_tokens max_completion_tokens temperature top_p stop seed
          frequency_penalty presence_penalty response_format reasoning_effort
          tool_choice parallel_tool_calls stream_options
        ].freeze
        MANAGED_OPTIONS = %i[max_completion_tokens reasoning_control].freeze

        module_function

        def map(options)
          mapped = options.reject { |key, _| MANAGED_OPTIONS.include?(key) }
          if options.key?(:max_completion_tokens)
            raise ArgumentError, "Specify max_completion_tokens or max_tokens, not both" if options.key?(:max_tokens)

            key = options[:model].to_s.start_with?("openai/") ? :max_completion_tokens : :max_tokens
            mapped[key] = options[:max_completion_tokens]
          end

          control = options[:reasoning_control]
          if control && control[:type] != :none
            unless control[:type] == :effort
              raise ArgumentError, "AI Gateway Chat Completions supports effort reasoning controls, got #{control.inspect}"
            end

            mapped[:reasoning_effort] = control.fetch(:value)
          end

          format = mapped[:response_format]
          mapped[:response_format] = { type: format } if format.is_a?(String)

          # Let the upstream choose its own defaults rather than inheriting
          # OpenAI token limits, cache settings, or temperature defaults.
          validate_options!(mapped)
          mapped
        end

        def validate_options!(mapped)
          unknown = mapped.keys - VALID_OPTIONS
          return if unknown.empty?

          raise ArgumentError,
            "Unknown Cloudflare AI Gateway options: #{unknown.join(', ')}. Valid options: #{VALID_OPTIONS.join(', ')}"
        end
      end
    end
  end
end
