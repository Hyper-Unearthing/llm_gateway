# frozen_string_literal: true

require_relative "../claude/input_mapper"

module LlmGateway
  module Adapters
    module ClaudeCode
      class InputMapper < Claude::InputMapper
        # Inherits all mapping from Claude::InputMapper
        # The client handles OAuth-specific transformations (tool names, system prompt)
      end
    end
  end
end
