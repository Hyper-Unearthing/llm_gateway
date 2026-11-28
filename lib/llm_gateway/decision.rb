# frozen_string_literal: true

require_relative "adapters/structs"
require_relative "decision_answers"

module LlmGateway
  # Provider-independent decision questions. Criteria and instructions deliberately
  # use text in this first version; provider-specific media formats are not portable.
  class PredicateQuestion < BaseStruct
    attribute :instructions, Types::String.constrained(min_size: 1)

    def type
      "predicate"
    end
  end

  class ChoiceQuestion < PredicateQuestion
    attribute :criteria, Types::Hash.map(Types::Coercible::String, Types::String.constrained(min_size: 1))

    def initialize(attributes = {})
      super
      raise ArgumentError, "Choice criteria must contain at least two options" if criteria.size < 2
      raise ArgumentError, "Choice values must not be empty" if criteria.keys.any?(&:empty?)
    end

    def type
      "choice"
    end
  end

  class ScoreQuestion < PredicateQuestion
    attribute :criteria, Types::Array.of(Types::String.constrained(min_size: 1)).constrained(min_size: 2, max_size: 10)

    def type
      "score"
    end
  end

  class DecisionRequest < BaseStruct
    attribute :message, Types::String.constrained(min_size: 1)
    attribute :questions, Types::Hash.map(
      Types::Coercible::String,
      Types.Instance(PredicateQuestion)
    ).default { {} }

    def initialize(attributes = {})
      super
      raise ArgumentError, "Question names must not be empty" if questions.keys.any?(&:empty?)
    end

    # Keep reusable base requests untouched when composing a question set.
    def with_question(name, question)
      name = name.to_s
      raise ArgumentError, "Question #{name.inspect} already exists" if questions.key?(name)

      self.class.new(attributes.merge(questions: questions.merge(name => question)))
    end
  end

  class PredicateAnswer < BaseStruct
    attribute :type, Types::String.enum("predicate")
    attribute :probability, Types::Float
  end

  class ChoiceAnswer < BaseStruct
    attribute :type, Types::String.enum("choice")
    attribute :choice, Types::String
    attribute :probabilities, Types::Hash
    attribute? :confidence, Types::Float.optional
  end

  class ScoreAnswer < BaseStruct
    attribute :type, Types::String.enum("score")
    attribute :score, Types::Float
    # Score probabilities and legend are keyed by integer level index.
    attribute :probabilities, Types::Hash
    attribute :legend, Types::Hash
    attribute? :confidence, Types::Float.optional
  end

  class RefusalAnswer < BaseStruct
    attribute :type, Types::String.enum("refusal")
  end

  class DecisionResponse < BaseStruct
    attribute? :id, Types::String.optional
    attribute :provider, Types::String
    attribute :api, Types::String.default("decisions".freeze)
    attribute :model, Types::String
    attribute :answers, Types.Instance(Data)
    attribute :usage, Types::Hash

    def to_h
      attributes.merge(answers: answers.to_h.transform_values(&:to_h))
    end
  end
end
