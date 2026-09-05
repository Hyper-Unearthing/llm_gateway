#!/usr/bin/env ruby
# frozen_string_literal: true

require "bigdecimal"
require "date"
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
NON_TEXT_GENERATION_FAMILIES = %w[gpt-image text-embedding whisper].freeze

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

def source_capability(model, key)
  value = model[key]
  value if value == true || value == false
end

def text_generation_capability(model)
  return false if NON_TEXT_GENERATION_FAMILIES.include?(model["family"])

  input_modalities = Array(model.dig("modalities", "input"))
  output_modalities = Array(model.dig("modalities", "output"))
  input_modalities.include?("text") && output_modalities.include?("text")
end

def invalid_metadata!(provider, id, message)
  raise ArgumentError, "Invalid models.dev metadata for #{provider}/#{id}: #{message}"
end

def non_negative_integer!(value, name, provider:, id:)
  normalized = Integer(value)
  if normalized.negative? || (value.is_a?(Numeric) && value != normalized)
    raise ArgumentError
  end

  normalized
rescue TypeError, ArgumentError, RangeError
  invalid_metadata!(provider, id, "#{name} must be a non-negative integer")
end

def date_for(value, name, provider:, id:)
  return nil if value.nil?
  invalid_metadata!(provider, id, "#{name} must be an ISO-8601 date") unless value.is_a?(String)

  Date.iso8601(value).iso8601
rescue Date::Error
  invalid_metadata!(provider, id, "#{name} must be an ISO-8601 date")
end

def normalize_source_value(value, provider:, id:)
  case value
  when String, Numeric, TrueClass, FalseClass, NilClass then value
  when Array then value.map { |item| normalize_source_value(item, provider:, id:) }
  when Hash
    value.each_with_object({}) do |(key, item), normalized|
      unless key.is_a?(String) || key.is_a?(Symbol)
        invalid_metadata!(provider, id, "reasoning option keys must be strings")
      end

      normalized[key.to_sym] = normalize_source_value(item, provider:, id:)
    end
  else
    invalid_metadata!(provider, id, "reasoning option attributes must contain JSON values")
  end
end

def reasoning_controls_for(model, provider:, id:)
  return nil unless model.key?("reasoning_options")

  options = model["reasoning_options"]
  unless options.is_a?(Array)
    invalid_metadata!(provider, id, "reasoning_options must be an array")
  end

  options.map.with_index do |option, index|
    unless option.is_a?(Hash)
      invalid_metadata!(provider, id, "reasoning_options[#{index}] must be an object")
    end

    option = normalize_source_value(option, provider:, id:)
    type = option[:type]
    unless type.is_a?(String) && !type.empty?
      invalid_metadata!(provider, id, "reasoning_options[#{index}].type must be a non-empty string")
    end

    case type
    when "effort"
      values = option[:values]
      unless values.is_a?(Array)
        invalid_metadata!(provider, id, "reasoning_options[#{index}].values must be an array")
      end
      unless values.compact.all? { |value| value.is_a?(String) }
        invalid_metadata!(provider, id, "reasoning_options[#{index}].values must contain strings or null")
      end

      option[:values] = values.compact.uniq
    when "budget_tokens"
      %i[min max].each do |boundary|
        next unless option.key?(boundary) && !option[boundary].nil?

        option[boundary] = non_negative_integer!(
          option[boundary], "reasoning_options[#{index}].#{boundary}", provider:, id:
        )
      end
      if option[:min] && option[:max] && option[:max] < option[:min]
        invalid_metadata!(provider, id, "reasoning_options[#{index}].max must not be below min")
      end
    end

    option
  end
end

def definitions_for(data, provider:)
  data.fetch(provider).fetch("models").map do |id, model|
    cost = model["cost"] || {}
    limit = model["limit"] || {}
    {
      provider: provider,
      id: id,
      name: model["name"] || id,
      source: :models_dev,
      release_date: date_for(model["release_date"], "release_date", provider:, id:),
      last_updated: date_for(model["last_updated"], "last_updated", provider:, id:),
      context_window: limit["context"],
      max_output_tokens: limit["output"],
      input_modalities: Array(model.dig("modalities", "input")),
      output_modalities: Array(model.dig("modalities", "output")),
      capabilities: {
        text_generation: text_generation_capability(model),
        tool_calling: source_capability(model, "tool_call"),
        structured_output: source_capability(model, "structured_output"),
        reasoning: source_capability(model, "reasoning")
      },
      reasoning_controls: reasoning_controls_for(model, provider:, id:),
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
