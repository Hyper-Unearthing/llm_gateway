# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Decisions
      class OutputMapper
        def self.map(response, request:, provider:, model:)
          new.map(response, request: request, provider: provider, model: model)
        end

        def map(response, request:, provider:, model:)
          raise Errors::InvalidDecisionResponse, "Expected a decision response object" unless response.is_a?(Hash)

          answers = named_answers(response.fetch(:answers)).to_h do |name, raw|
            [ name, answer(raw, request.questions[name]) ]
          end
          DecisionResponse.new(
            id: response[:id], provider: provider, model: response[:model] || model,
            answers: DecisionAnswers.build(answers), usage: usage(response[:usage] || {})
          )
        rescue KeyError, TypeError, ArgumentError, Dry::Struct::Error => error
          raise Errors::InvalidDecisionResponse, "Invalid decision response: #{error.message}"
        end

        private

        def named_answers(answers)
          raise Errors::InvalidDecisionResponse, "Expected named decision answers" unless answers.is_a?(Hash)

          normalize_options(answers, integer_keys: false) { |answer| answer }
        end

        def answer(raw, question)
          raise Errors::InvalidDecisionResponse, "Expected a decision answer object" unless raw.is_a?(Hash)

          case raw.fetch(:type)
          when "refusal"
            RefusalAnswer.new(type: "refusal")
          when "noul", "predicate"
            PredicateAnswer.new(type: "predicate", probability: Float(raw.fetch(raw[:type] == "noul" ? :noul : :probability)))
          when "choice"
            ChoiceAnswer.new(
              type: "choice", choice: raw.fetch(:choice).to_s,
              confidence: confidence(raw), probabilities: probabilities(raw, integer_keys: false)
            )
          when "score"
            ScoreAnswer.new(
              type: "score", score: Float(raw.fetch(:score)), confidence: confidence(raw),
              probabilities: probabilities(raw, integer_keys: true), legend: legend(raw, question)
            )
          else
            raise Errors::InvalidDecisionResponse, "Unsupported decision answer type #{raw[:type].inspect}"
          end
        end

        def probabilities(raw, integer_keys:)
          distribution = raw.fetch(:probabilities)
          raise Errors::InvalidDecisionResponse, "Expected a probability map" unless distribution.is_a?(Hash)

          normalize_probabilities(distribution, integer_keys: integer_keys)
        end

        def normalize_probabilities(entries, integer_keys:)
          normalize_options(entries, integer_keys: integer_keys) { |value| Float(value) }
        end

        # Reject collisions introduced by normalization rather than silently
        # discarding provider data. Mathematical correctness belongs to providers.
        def normalize_options(entries, integer_keys:)
          entries.each_with_object({}) do |(key, value), result|
            key = integer_keys ? Integer(key.to_s, 10) : key.to_s
            raise Errors::InvalidDecisionResponse, "Duplicate normalized option #{key.inspect}" if result.key?(key)

            result[key] = yield value
          end
        end

        def legend(raw, question)
          if raw[:legend]
            normalize_options(raw[:legend], integer_keys: true) { |description| description }
          elsif question.is_a?(ScoreQuestion)
            question.criteria.each_with_index.to_h { |description, index| [ index, description ] }
          else
            {}
          end
        end

        def confidence(raw)
          Float(raw[:confidence]) unless raw[:confidence].nil?
        end

        def usage(raw)
          cache_read = raw.dig(:input_tokens_details, :cached_tokens).to_i
          cache_write = (raw.dig(:input_tokens_details, :cache_write_tokens) || raw[:cache_write_tokens]).to_i
          input = [ raw[:input_tokens].to_i - cache_read - cache_write, 0 ].max
          output = raw[:output_tokens].to_i
          {
            input: input,
            cache_read: cache_read,
            cache_write: cache_write,
            output: output,
            total: input + cache_read + cache_write + output,
            raw: raw
          }
        end
      end
    end
  end
end
