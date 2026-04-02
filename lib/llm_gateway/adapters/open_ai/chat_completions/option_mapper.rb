# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAi
      module ChatCompletions
        module OptionMapper
          VALID_REASONING_LEVELS = %w[low medium high xhigh].freeze

          module_function

          def map(options)
            mapped_options = options.dup
            mapped_options[:max_completion_tokens] ||= 20_480

            return mapped_options unless mapped_options.key?(:reasoning)

            reasoning = mapped_options.delete(:reasoning)
            return mapped_options if reasoning.nil? || reasoning.to_s == "none"

            mapped_options.merge(reasoning_effort: normalize_reasoning_effort(reasoning))
          end

          def normalize_reasoning_effort(reasoning)
            effort = reasoning.to_s
            return effort if VALID_REASONING_LEVELS.include?(effort)

            raise ArgumentError, "Invalid reasoning '#{reasoning}'. Use 'none', 'low', 'medium', 'high', or 'xhigh'."
          end
        end
      end
    end
  end
end
