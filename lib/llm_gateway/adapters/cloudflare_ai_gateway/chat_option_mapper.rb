# frozen_string_literal: true

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      module ChatOptionMapper
        # Source: https://developers.cloudflare.com/ai-gateway/usage/rest-api/
        # Schema: https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create/index.md
        # API: Cloudflare REST Chat Completions; accessed 2026-11-01.
        # Reference body fields: model, messages, audio, frequency_penalty,
        # function_call, functions, logit_bias, logprobs, max_completion_tokens,
        # max_tokens, metadata, modalities, n, parallel_tool_calls, prediction,
        # presence_penalty, prompt_cache_key, prompt_cache_retention,
        # reasoning_effort, response_format, safety_identifier, seed,
        # service_tier, stop, store, stream, stream_options, temperature,
        # tool_choice, tools, top_logprobs, top_p, user, verbosity,
        # web_search_options. Expose a conservative cross-provider subset;
        # transcript/system/tools/stream are owned by the adapter, not options.
        VALID_OPTIONS = %i[
          model max_tokens max_completion_tokens temperature top_p stop seed
          frequency_penalty presence_penalty response_format reasoning_effort
          tool_choice parallel_tool_calls stream_options
        ].freeze
        MANAGED_OPTIONS = %i[max_completion_tokens reasoning_control].freeze

        module_function

        def map(options)
          mapped = options.except(*MANAGED_OPTIONS)
          if options.key?(:max_completion_tokens)
            raise ArgumentError, "Specify max_completion_tokens or max_tokens, not both" if options.key?(:max_tokens)

            key = options[:model].to_s.start_with?("openai/") ? :max_completion_tokens : :max_tokens
            mapped[key] = options[:max_completion_tokens]
          end
          control = options[:reasoning_control]
          if control && control[:type] != :none
            unless control[:type] == :effort
              raise ArgumentError, "Cloudflare Chat Completions requires effort reasoning controls, got #{control.inspect}"
            end

            mapped[:reasoning_effort] = control.fetch(:value)
          end
          format = mapped[:response_format]
          mapped[:response_format] = { type: format } if format.is_a?(String)
          choice = mapped[:tool_choice]
          if choice.is_a?(Hash) && %w[none auto].include?(choice[:type].to_s)
            mapped[:tool_choice] = choice[:type].to_s
          end
          validate_options!(mapped)
          mapped
        end

        def validate_options!(mapped)
          unknown = mapped.keys - VALID_OPTIONS
          return if unknown.empty?

          raise ArgumentError,
            "Unknown Cloudflare Chat Completions options: #{unknown.join(', ')}. Valid options: #{VALID_OPTIONS.join(', ')}"
        end
      end
    end
  end
end
