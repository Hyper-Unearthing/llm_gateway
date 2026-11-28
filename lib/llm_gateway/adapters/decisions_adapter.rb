# frozen_string_literal: true

require_relative "adapter"
require_relative "decisions/input_mapper"
require_relative "decisions/output_mapper"

module LlmGateway
  module Adapters
    # Non-streaming counterpart to Adapter#stream. Concrete decision adapters
    # still use the same provider declarations, catalog resolution and .build API.
    class DecisionsAdapter < Adapter
      class << self
        def supports_model?(model)
          model.provider == provider && model.supports?(:decisions) == true &&
            !LlmGateway.models.find(provider: model.provider, id: model.id).nil?
        end
      end

      def decide(request, model:)
        raise ArgumentError, "Expected a DecisionRequest" unless request.is_a?(DecisionRequest)
        raise ArgumentError, "At least one question is required" if request.questions.empty?

        model = resolve_model!(model)
        response = client.decisions(**input_mapper.map(request), model: self.class.provider_model_key(model))
        result = output_mapper.map(response, request: request, provider: provider, model: model.id)
        cost = Models::CostCalculator.calculate(model, result.usage, api: :decisions)
        return result unless cost

        DecisionResponse.new(result.attributes.merge(usage: result.usage.merge(cost: cost)))
      end

      def raw_stream(*)
        raise NotImplementedError, "Decision adapters support #decide, not streaming"
      end

      def stream(*)
        raise NotImplementedError, "Decision adapters support #decide, not streaming"
      end

      private

      def input_mapper
        Decisions::InputMapper
      end

      def output_mapper
        Decisions::OutputMapper
      end
    end
  end
end
