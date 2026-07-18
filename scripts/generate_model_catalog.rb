#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "json"
require "net/http"

SOURCE_URL = "https://models.dev/api.json"
OUTPUT_PATH = File.expand_path("../lib/llm_gateway/models/generated.json", __dir__)
OPENAI_LONG_CONTEXT_INPUT_THRESHOLD = 272_000
OPENAI_LONG_CONTEXT_PRICING_MODEL_IDS = %w[
  gpt-5.4
  gpt-5.4-pro
  gpt-5.5
  gpt-5.5-pro
  gpt-5.6-sol
  gpt-5.6-terra
  gpt-5.6-luna
].freeze

PROVIDERS = %w[anthropic openai groq].freeze

source =
  if ARGV.first
    JSON.parse(File.read(ARGV.first))
  else
    response = Net::HTTP.get_response(URI(SOURCE_URL))
    abort "Failed to fetch #{SOURCE_URL}: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

def pricing_for(cost, provider:, id:)
  return nil if cost.empty?

  pricing = {
    input: cost.fetch("input", 0).to_s,
    output: cost.fetch("output", 0).to_s,
    cache_read: cost.fetch("cache_read", 0).to_s,
    cache_write: cost.fetch("cache_write", 0).to_s
  }
  return pricing unless provider == "openai" && OPENAI_LONG_CONTEXT_PRICING_MODEL_IDS.include?(id)

  pricing.merge(
    tiers: [
      {
        input_tokens_above: OPENAI_LONG_CONTEXT_INPUT_THRESHOLD,
        input: (BigDecimal(pricing[:input]) * 2).to_s("F"),
        output: (BigDecimal(pricing[:output]) * 1.5).to_s("F"),
        cache_read: (BigDecimal(pricing[:cache_read]) * 2).to_s("F"),
        cache_write: (BigDecimal(pricing[:cache_write]) * 2).to_s("F")
      }
    ]
  )
end

def definitions_for(data, provider:)
  data.fetch(provider).fetch("models").filter_map do |id, model|
    next unless model["tool_call"] == true

    cost = model["cost"] || {}
    limit = model["limit"] || {}
    {
      provider: provider,
      id: id,
      name: model["name"] || id,
      source: :models_dev,
      context_window: limit["context"],
      max_output_tokens: limit["output"],
      input_modalities: Array(model.dig("modalities", "input")).filter_map do |modality|
        modality.to_sym if %w[text image].include?(modality)
      end,
      reasoning: model["reasoning"] == true,
      pricing: pricing_for(cost, provider:, id:)
    }.compact
  end
end

definitions = PROVIDERS.flat_map { |provider| definitions_for(source, provider:) }

payload = {
  source: SOURCE_URL,
  definitions: definitions.sort_by { |model| [ model[:provider], model[:id] ] }
}

File.write(OUTPUT_PATH, JSON.pretty_generate(payload) + "\n")
puts "Wrote #{definitions.size} definitions to #{OUTPUT_PATH}"
