# frozen_string_literal: true

require_relative "../claude/output_mapper"

module LlmGateway
  module Adapters
    module ClaudeCode
      class OutputMapper < Claude::OutputMapper
      end
    end
  end
end
