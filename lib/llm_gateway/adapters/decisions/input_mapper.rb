# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Decisions
      # Jev and Clef share the System One wire format.
      class InputMapper
        def self.map(request)
          {
            state: request.message,
            questions: request.questions.transform_values do |question|
              result = { type: question.type == "predicate" ? "noul" : question.type, instructions: question.instructions }
              result[:criteria] = question.criteria if question.respond_to?(:criteria)
              result
            end
          }
        end
      end
    end
  end
end
