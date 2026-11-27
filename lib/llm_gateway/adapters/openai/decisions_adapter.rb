# frozen_string_literal: true

require_relative "../decisions_adapter"
require_relative "decisions/input_mapper"
require_relative "decisions/output_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      class DecisionsAdapter < LlmGateway::Adapters::DecisionsAdapter
        provider "openai"
        client_class LlmGateway::Clients::OpenAI

        def decide(request, model:)
          if request.is_a?(DecisionRequest) && request.questions.size > 400
            raise ArgumentError, "OpenAI Decisions supports at most 400 questions"
          end

          super
        end

        private

        def input_mapper
          Decisions::InputMapper
        end

        def output_mapper
          Decisions::OutputMapper
        end
      end

      Decisions.extend(DefinitionFacade)
      Decisions.define_adapter(DecisionsAdapter)
    end
  end
end
