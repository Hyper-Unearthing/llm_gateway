# frozen_string_literal: true

module LlmGateway
  module Models
    module Explicit
      # Models missing from the upstream catalog, plus legacy IDs used by recordings.
      # https://docs.typesafe.ai/models
      # https://developers.openai.com/api/docs/guides/decisions
      # https://developers.cloudflare.com/workers-ai/models/clef/
      # https://developers.cloudflare.com/workers-ai/models/clef-flash/
      DEFINITIONS = [
        {
          provider: "typesafe",
          id: "jev-latest",
          name: "Jev (latest)",
          source: :explicit,
          context_window: 65_536,
          input_modalities: %i[text image],
          output_modalities: [],
          capabilities: { decisions: true, text_generation: false },
          pricing: { input: "0.042", output: "0" }
        },
        {
          provider: "typesafe",
          id: "jev-1.14.0",
          name: "Jev 1.14",
          source: :explicit,
          release_date: "2026-10-14",
          context_window: 65_536,
          input_modalities: %i[text image],
          output_modalities: [],
          capabilities: { decisions: true, text_generation: false },
          pricing: { input: "0.042", output: "0" }
        },
        {
          provider: "typesafe",
          id: "jev-1.13.0",
          name: "Jev 1.13",
          source: :explicit,
          context_window: 65_536,
          input_modalities: %i[text image],
          output_modalities: [],
          capabilities: { decisions: true, text_generation: false },
          pricing: { input: "0.042", output: "0" }
        },
        {
          provider: "openai",
          id: "gpt-6-luna",
          name: "GPT-6 Luna",
          source: :explicit,
          release_date: "2026-09-22",
          last_updated: "2026-09-22",
          context_window: 1_050_000,
          max_output_tokens: 128_000,
          input_modalities: %i[text image pdf],
          output_modalities: %i[text],
          capabilities: {
            text_generation: true,
            tool_calling: true,
            structured_output: true,
            reasoning: true,
            decisions: true
          },
          reasoning_controls: [ { type: "effort", values: %w[none low medium high xhigh max] } ],
          pricing: { input: "0.1", output: "0.5", cache_read: "0.01", cache_write: "0.125" },
          # Decisions shares the model ID but does not charge for output tokens.
          api_pricing: {
            decisions: { input: "0.1", output: "0", cache_read: "0.01", cache_write: "0.125" }
          }
        },
        {
          provider: "cloudflare",
          id: "@cf/cloudflare/clef",
          name: "Clef",
          source: :explicit,
          context_window: 65_536,
          input_modalities: %i[text image video],
          output_modalities: [],
          capabilities: { decisions: true, text_generation: false },
          pricing: { input: "0.24", output: "0" }
        },
        {
          provider: "cloudflare",
          id: "@cf/cloudflare/clef-flash",
          name: "Clef Flash",
          source: :explicit,
          context_window: 24_576,
          input_modalities: %i[text image video],
          output_modalities: [],
          capabilities: { decisions: true, text_generation: false },
          pricing: { input: "0.038", output: "0" }
        },
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
