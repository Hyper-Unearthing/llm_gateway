# frozen_string_literal: true

module LlmGateway
  module Adapters
    module ReasoningEffortMapper
      # Ordered comparable effort levels used for closest-match mapping. The
      # accepted public union also includes non-ordered provider controls
      # `none` and `default` below.
      # Official docs checked:
      # OpenAI: none/minimal/low/medium/high/xhigh; Anthropic: low/medium/high/xhigh/max;
      # Groq: model-specific none/default or low/medium/high.
      LEVELS = %w[minimal low medium high xhigh max].freeze
      DEFAULT_LEVEL = "default"
      DISABLED_LEVEL = "none"
      ACCEPTED_LEVELS = ([ DISABLED_LEVEL, DEFAULT_LEVEL ] + LEVELS).freeze

      module_function

      def normalize(reasoning)
        effort = reasoning.to_s
        return effort if ACCEPTED_LEVELS.include?(effort)

        raise ArgumentError, "Invalid reasoning '#{reasoning}'. Use #{accepted_levels_sentence}."
      end

      def closest_supported(reasoning, supported_levels)
        effort = normalize(reasoning)
        return effort if effort == DISABLED_LEVEL

        supported = supported_levels.map(&:to_s)
        return effort if supported.include?(effort)

        requested_effort = effort == DEFAULT_LEVEL ? "medium" : effort
        effort_index = level_index(requested_effort)
        supported.min_by do |supported_effort|
          supported_index = level_index(supported_effort)

          [ (supported_index - effort_index).abs, supported_index ]
        end
      end

      def level_index(effort)
        return LEVELS.index("medium") if effort == DEFAULT_LEVEL

        LEVELS.index(effort) || raise(ArgumentError, "Unsupported internal reasoning level '#{effort}'")
      end

      def accepted_levels_sentence
        quoted = ACCEPTED_LEVELS.map { |level| "'#{level}'" }
        "#{quoted[0...-1].join(', ')}, or #{quoted[-1]}"
      end
    end
  end
end
