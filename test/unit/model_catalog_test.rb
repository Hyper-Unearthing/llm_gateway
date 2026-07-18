# frozen_string_literal: true

require "test_helper"

class ModelCatalogTest < Test
  class RestrictedAliasAdapter < LlmGateway::Adapters::Adapter
    provider "openai"
    client_class LlmGateway::Clients::OpenAI

    def self.supports_model?(model)
      model.provider == provider && model.id == "gpt-5.4"
    end

    def self.provider_model_key(model)
      "wire/#{model.id}"
    end
  end

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
            id: "resp_1",
            model: model,
            status: "completed",
            output: [],
            usage: { input_tokens: 13, output_tokens: 9 }
          }
        }
      }
    end
  end

  test "one provider model definition is shared by multiple adapters" do
    model = LlmGateway.models.fetch("openai/gpt-5.4")

    assert_same model, LlmGateway.models.fetch(provider: "openai", id: "gpt-5.4")
    assert LlmGateway::Adapters::OpenAI::ResponsesAdapter.supports_model?(model)
    assert LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter.supports_model?(model)
    assert LlmGateway::Adapters::OpenAICodex::ResponsesAdapter.supports_model?(model)
    assert_raises(KeyError) { LlmGateway.models.fetch("openai-responses/gpt-5.4") }
  end

  test "catalog preserves IDs containing slashes with keyword lookup" do
    model = LlmGateway.models.fetch(provider: "groq", id: "openai/gpt-oss-120b")

    assert_equal "openai/gpt-oss-120b", model.id
    assert_same model, LlmGateway.models.fetch("groq/openai/gpt-oss-120b")
    assert LlmGateway::Adapters::Groq::ChatCompletionsAdapter.supports_model?(model)
    refute LlmGateway::Adapters::OpenAI::ResponsesAdapter.supports_model?(model)
  end

  test "catalog contains model definitions without adapter compatibility records" do
    definition = LlmGateway::Models::Definition.new(provider: "test", id: "model")
    catalog = LlmGateway::Models::Catalog.new([ definition ])

    assert_same definition, catalog.fetch(provider: "test", id: "model")
    assert_equal [ definition ], catalog.all(provider: "test")
  end

  test "adapter classes own model restrictions and provider model keys" do
    supported = LlmGateway.models.fetch("openai/gpt-5.4")
    unsupported = LlmGateway.models.fetch("openai/gpt-5.1")

    assert RestrictedAliasAdapter.supports_model?(supported)
    refute RestrictedAliasAdapter.supports_model?(unsupported)
    assert_equal "wire/gpt-5.4", RestrictedAliasAdapter.provider_model_key(supported)
    assert_same supported, RestrictedAliasAdapter.model_for_provider_model_key("wire/gpt-5.4")
    assert_raises(LlmGateway::Errors::UnsupportedModelForAdapter) do
      RestrictedAliasAdapter.resolve_model!(unsupported)
    end
  end

  test "adapter sends provider model string and adds numeric cost" do
    client = CatalogOpenAIClient.new(api_key: "test-key")
    adapter = LlmGateway::Adapters::OpenAI::ResponsesAdapter.new(client)
    model = LlmGateway.models.fetch("openai/gpt-5.5")

    result = adapter.stream("Hi", model: model)

    assert_equal "gpt-5.5", client.requested_model
    assert_equal BigDecimal("0.000065"), result.usage.dig(:cost, :input)
    assert_equal BigDecimal("0.00027"), result.usage.dig(:cost, :output)
    assert_equal BigDecimal("0.000335"), result.usage.dig(:cost, :total)
  end

  test "adapter canonicalizes model metadata before calculating cost" do
    client = CatalogOpenAIClient.new(api_key: "test-key")
    adapter = LlmGateway::Adapters::OpenAI::ResponsesAdapter.new(client)
    model = LlmGateway::Models::Definition.new(provider: "openai", id: "gpt-5.5")

    result = adapter.stream("Hi", model: model)

    assert_equal BigDecimal("0.000335"), result.usage.dig(:cost, :total)
  end

  test "adapter rejects provider mismatches and unsupported combinations" do
    responses = LlmGateway::Adapters::OpenAI::Responses.build(api_key: "test")

    assert_raises(LlmGateway::Errors::ModelProviderMismatch) do
      responses.stream("Hi", model: LlmGateway.models.fetch("anthropic/claude-sonnet-4-20250514"))
    end
    assert_raises(LlmGateway::Errors::UnsupportedModelForAdapter) do
      responses.stream("Hi", model: LlmGateway::Models::Definition.new(provider: "openai", id: "unsupported"))
    end
  end

  test "catalog includes text generation models without tool calling" do
    model = LlmGateway.models.fetch("openai/gpt-3.5-turbo")

    assert model.supports?(:text_generation)
    refute model.supports?(:tool_calling)
    assert model.supports_input?(:text)
    assert model.supports_output?(:text)
  end

  test "model capabilities are tri-state and modalities are queryable" do
    definition = LlmGateway::Models::Definition.new(
      provider: "test",
      id: "capabilities",
      input_modalities: %i[text image],
      output_modalities: %i[text],
      capabilities: {
        text_generation: true,
        tool_calling: false,
        structured_output: nil
      }
    )

    assert_equal true, definition.supports?(:text_generation)
    assert_equal false, definition.supports?(:tool_calling)
    assert_nil definition.supports?(:structured_output)
    assert_nil definition.supports?(:reasoning)
    assert definition.supports_input?("image")
    refute definition.supports_output?(:image)
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(
        provider: "test", id: "invalid-capability", capabilities: { tool_calling: "maybe" }
      )
    end
  end

  test "users can register definitions and explicitly replace catalog metadata" do
    original = LlmGateway.models.register(
      provider: "custom-provider",
      id: "runtime-model",
      capabilities: { text_generation: true, tool_calling: nil },
      pricing: { input: "1", output: "2" }
    )

    assert_same original, LlmGateway.models.fetch("custom-provider/runtime-model")
    assert_equal :user, original.source
    assert_raises(ArgumentError) { LlmGateway.models.register(original) }

    replacement = LlmGateway::Models::Definition.new(
      provider: "custom-provider",
      id: "runtime-model",
      source: :user,
      capabilities: { text_generation: true, tool_calling: true },
      pricing: { input: "3", output: "4" }
    )
    LlmGateway.models.register(replacement, replace: true)

    assert_same replacement, LlmGateway.models.fetch("custom-provider/runtime-model")

    LlmGateway.models.reset_catalog!

    assert_same replacement, LlmGateway.models.fetch("custom-provider/runtime-model")
  end

  test "model definitions reject invalid structural values" do
    assert_raises(ArgumentError) { LlmGateway::Models::Definition.new(provider: "", id: "model") }
    assert_raises(ArgumentError) { LlmGateway::Models::Definition.new(provider: "test", id: "  ") }
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(provider: "test", id: "model", context_window: -1)
    end
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(provider: "test", id: "model", max_output_tokens: -1)
    end
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(provider: "test", id: "model", context_window: 1.5)
    end
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(
        provider: "test", id: "model", pricing: { input: "-1", output: "2" }
      )
    end
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(
        provider: "test",
        id: "model",
        pricing: {
          input: "1",
          output: "2",
          tiers: [ { input_tokens_above: -1, input: "1", output: "2" } ]
        }
      )
    end
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(
        provider: "test",
        id: "model",
        pricing: {
          input: "1",
          output: "2",
          tiers: [ { input_tokens_above: 10.5, input: "1", output: "2" } ]
        }
      )
    end
  end

  test "cost calculator uses normalized buckets and pricing tiers" do
    definition = LlmGateway::Models::Definition.new(
      provider: "test", id: "tiered",
      pricing: {
        input: "1",
        output: "2",
        cache_read: "0.5",
        cache_write: "1.25",
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
