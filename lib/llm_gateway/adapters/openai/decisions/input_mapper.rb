# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAI
      module Decisions
        class InputMapper
          # https://developers.openai.com/api/docs/guides/decisions
          def self.map(request)
            {
              input: request.message,
              questions: request.questions.map do |name, question|
                result = { name: name, type: question.type, instructions: question.instructions }
                case question.type
                when "choice"
                  result[:choices] = question.criteria.map { |value, description| { value: value, description: description } }
                when "score"
                  result[:levels] = question.criteria.each_with_index.map do |description, index|
                    { label: index.to_s, description: description }
                  end
                end
                result
              end
            }
          end
        end
      end
    end
  end
end
