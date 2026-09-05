# frozen_string_literal: true

module LlmGateway
  module Models
    module Explicit
      # Legacy model IDs remain here because recorded streams still use them.
      DEFINITIONS = [
        {
          provider: "anthropic",
          id: "claude-sonnet-4-20250514",
          name: "Claude Sonnet 4",
          source: :explicit,
          context_window: 200_000,
          max_output_tokens: 64_000,
          input_modalities: %i[text image],
          output_modalities: %i[text],
          capabilities: {
            text_generation: true,
            tool_calling: true,
            structured_output: true,
            reasoning: true
          },
          reasoning_controls: [ { type: "budget_tokens", min: 1_024, max: 13_312 } ],
          pricing: { input: "3", output: "15", cache_read: "0.3", cache_write: "3.75" }
        },
        {
          provider: "groq",
          id: "meta-llama/llama-4-scout-17b-16e-instruct",
          name: "Llama 4 Scout 17B 16E",
          source: :explicit,
          context_window: 131_072,
          max_output_tokens: 8_192,
          input_modalities: %i[text image],
          output_modalities: %i[text],
          capabilities: {
            text_generation: true,
            tool_calling: true,
            structured_output: true,
            reasoning: false
          },
          pricing: { input: "0.11", output: "0.34", cache_read: "0", cache_write: "0" }
        }
      ].freeze
    end
  end
end
