# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAI
      module Responses
        module OptionMapper
          include LlmGateway::Adapters::OpenAI::PromptCacheOptionMapper

          VALID_REASONING_LEVELS = %w[low medium high xhigh].freeze

          module_function

          def map(options)
            mapped_options = options.dup

            max_completion_tokens = mapped_options.delete(:max_completion_tokens)
            mapped_options[:max_output_tokens] = max_completion_tokens || mapped_options[:max_output_tokens] || 20_480

            map_cache_key!(mapped_options)
            map_prompt_cache_retention!(mapped_options)

            return mapped_options unless mapped_options.key?(:reasoning)

            reasoning = mapped_options.delete(:reasoning)
            return mapped_options if reasoning.nil? || reasoning.to_s == "none"

            mapped_options.merge(reasoning: normalize_reasoning(reasoning))
          end

          def normalize_reasoning(reasoning)
            effort = reasoning.to_s
            return { effort: effort, summary: "detailed" } if VALID_REASONING_LEVELS.include?(effort)

            raise ArgumentError, "Invalid reasoning '#{reasoning}'. Use 'none', 'low', 'medium', 'high', or 'xhigh'."
          end
        end
      end
    end
  end
end
