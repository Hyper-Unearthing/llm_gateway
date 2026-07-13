# frozen_string_literal: true

require "test_helper"

class ModelCatalogTest < Test
  class CatalogOpenAIClient < LlmGateway::Clients::OpenAI
    attr_reader :requested_model

    def stream_responses(_messages, tools:, system:, model:, **_options)
      @requested_model = model
      yield(response_completed_chunk(model))
    end

    def response_completed_chunk(model)
      {
        event: "response.completed",
        data: {
          response: {
            id: "resp_1", model: model, status: "completed", output: [],
            usage: { input_tokens: 13, output_tokens: 9 }
          }
        }
      }
    end
  end

  test "one provider model definition is shared by multiple adapters" do
    model = LlmGateway.models.fetch("openai/gpt-5.4")

    assert_same model, LlmGateway.models.fetch(provider: "openai", id: "gpt-5.4")
    assert LlmGateway.models.supported_by?(model, adapter: "openai-responses")
    assert LlmGateway.models.supported_by?(model, adapter: "openai-completions")
    assert LlmGateway.models.supported_by?(model, adapter: "openai-codex")
    assert_raises(KeyError) { LlmGateway.models.fetch("openai-responses/gpt-5.4") }
  end

  test "catalog preserves IDs containing slashes with keyword lookup" do
    model = LlmGateway.models.fetch(provider: "groq", id: "openai/gpt-oss-120b")

    assert_equal "openai/gpt-oss-120b", model.id
    assert_same model, LlmGateway.models.fetch("groq/openai/gpt-oss-120b")
    assert LlmGateway.models.supported_by?(model, adapter: "groq-completions")
    refute LlmGateway.models.supported_by?(model, adapter: "openai-responses")
  end

  test "catalog supports explicit compatibility records" do
    definition = LlmGateway::Models::Definition.new(provider: "test", id: "model")
    compatibility = LlmGateway::Models::Compatibility.new(
      provider: "test", model_id: "model", adapter_id: "test-adapter", provider_model_key: "wire-model"
    )
    catalog = LlmGateway::Models::Catalog.new([ definition ], [ compatibility ])

    assert_same definition, catalog.fetch(provider: "test", id: "model")
    assert_equal "wire-model", catalog.compatibility_for(definition, adapter: "test-adapter").provider_model_key
    assert catalog.validate_compatibility!(definition, provider: "test", adapter: "test-adapter")
    assert_equal "wire-model", catalog.provider_model_key_for!(definition, provider: "test", adapter: "test-adapter")
    assert catalog.supported_by?(definition, adapter: "test-adapter")
    refute catalog.supported_by?(definition, adapter: "other")
  end

  test "adapter sends compatibility request model string and adds numeric cost" do
    client = CatalogOpenAIClient.new(api_key: "test-key")
    adapter = LlmGateway::Adapters::OpenAI::ResponsesAdapter.new(
      client, provider: "openai", adapter_id: "openai-responses"
    )
    model = LlmGateway.models.fetch("openai/gpt-5.5")

    result = adapter.stream("Hi", model: model)

    assert_equal "gpt-5.5", client.requested_model
    assert_equal BigDecimal("0.000065"), result.usage.dig(:cost, :input)
    assert_equal BigDecimal("0.00027"), result.usage.dig(:cost, :output)
    assert_equal BigDecimal("0.000335"), result.usage.dig(:cost, :total)
  end

  test "adapter rejects strings, provider mismatches, and unsupported combinations" do
    responses = LlmGateway.build_adapter(adapter: "openai-responses", api_key: "test")

    assert_raises(LlmGateway::Errors::InvalidModelDefinition) { responses.stream("Hi", model: "gpt-5.4") }
    assert_raises(LlmGateway::Errors::ModelProviderMismatch) do
      responses.stream("Hi", model: LlmGateway.models.fetch("anthropic/claude-sonnet-4-20250514"))
    end
    assert_raises(LlmGateway::Errors::UnsupportedModelForAdapter) do
      responses.stream("Hi", model: LlmGateway::Models::Definition.new(provider: "openai", id: "unsupported"))
    end
  end

  test "cost calculator uses normalized buckets and pricing tiers" do
    definition = LlmGateway::Models::Definition.new(
      provider: "test", id: "tiered",
      pricing: {
        input: "1", output: "2", cache_read: "0.5", cache_write: "1.25",
        tiers: [ { input_tokens_above: 10, input: "3", output: "4", cache_read: "1.5", cache_write: "2.5" } ]
      }
    )

    cost = LlmGateway::Models::CostCalculator.calculate(
      definition, input: 10, cache_read: 1, cache_write: 1, output: 2
    )

    assert_equal BigDecimal("0.00003"), cost[:input]
    assert_equal BigDecimal("0.000008"), cost[:output]
    assert_equal BigDecimal("0.0000015"), cost[:cache_read]
    assert_equal BigDecimal("0.0000025"), cost[:cache_write]
    assert_equal BigDecimal("0.000042"), cost[:total]
  end
end
