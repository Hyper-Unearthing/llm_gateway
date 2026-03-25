# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAi
      module Responses
        module OptionMapper
          VALID_REASONING_LEVELS = %w[low medium high xhigh].freeze

          module_function

          def map(options)
            return options unless options.key?(:reasoning)

            reasoning = options[:reasoning]
            mapped_options = options.reject { |key, _| key == :reasoning }
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
