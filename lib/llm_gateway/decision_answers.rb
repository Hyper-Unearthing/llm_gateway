# frozen_string_literal: true

module LlmGateway
  module DecisionAnswers
    def self.build(answers)
      values = answers.transform_keys { |name| name.to_s.to_sym }
      # Classes are response-local; do not cache caller-defined question schemas.
      Data.define(*values.keys).new(**values)
    end
  end
end
