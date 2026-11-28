# frozen_string_literal: true

require_relative "../../decisions/output_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      module Decisions
        class OutputMapper < LlmGateway::Adapters::Decisions::OutputMapper
          private

          def named_answers(answers)
            raise Errors::InvalidDecisionResponse, "Expected a decision answers array" unless answers.is_a?(Array)

            result = {}
            answers.each do |answer|
              raise Errors::InvalidDecisionResponse, "Expected a decision answer object" unless answer.is_a?(Hash)

              name = answer.fetch(:name).to_s
              raise Errors::InvalidDecisionResponse, "Duplicate decision answer #{name.inspect}" if result.key?(name)

              result[name] = answer
            end
            result
          end

          def legend(raw, question)
            return super if question.is_a?(ScoreQuestion)

            pairs = raw.fetch(:probabilities).map { |entry| [ entry.fetch(:value), entry.fetch(:label) ] }
            normalize_options(pairs, integer_keys: true) { |label| label }
          end

          def probabilities(raw, integer_keys:)
            entries = raw.fetch(:probabilities)
            raise Errors::InvalidDecisionResponse, "Expected a probabilities array" unless entries.is_a?(Array)

            pairs = entries.map do |entry|
              raise Errors::InvalidDecisionResponse, "Expected a probability object" unless entry.is_a?(Hash)

              [ entry.fetch(:value), entry.fetch(:probability) ]
            end
            normalize_probabilities(pairs, integer_keys: integer_keys)
          end
        end
      end
    end
  end
end
