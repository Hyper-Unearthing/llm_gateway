# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Claude
      class OutputMapper
        extend LlmGateway::FluentMapper

        map :id
        map :model
        map :usage
        map :choices do |_, _|
          # Claude returns content directly at root level, not in a choices array
          # We need to construct the choices array from the full response data
          [ {
            content: @data[:content] || [], # Use content directly from Claude response
            finish_reason: @data[:stop_reason],
            role: "assistant"
          } ]
        end
      end
    end
  end
end
