# frozen_string_literal: true

module LlmGateway
  module Models
    module Explicit
      # The legacy Sonnet ID remains here because recorded streams still use it.
      DEFINITIONS = [
        {
          provider: "anthropic",
          id: "claude-sonnet-4-20250514",
          name: "Claude Sonnet 4",
          source: :explicit,
          context_window: 200_000,
          max_output_tokens: 64_000,
          input_modalities: %i[text image],
          reasoning: true,
          pricing: { input: "3", output: "15", cache_read: "0.3", cache_write: "3.75" }
        }
      ].freeze
    end
  end
end
