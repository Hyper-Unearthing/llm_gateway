# frozen_string_literal: true

require "test_helper"

class CloudflareAIGatewayOptionMapperTest < Test
  Mapper = LlmGateway::Adapters::CloudflareAIGateway::OptionMapper
  SCHEMA = { type: "object", properties: { answer: { type: "string" } } }.freeze

  test "passes mapped managed options and provider-native options through adapter to client" do
    client = FakeClient.new
    adapter = LlmGateway::Adapters::CloudflareAIGateway::MessagesAdapter.new(client)
    model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: "anthropic/claude-haiku-5.5")

    response = adapter.stream(
      "hello",
      model: model, reasoning: "high", max_completion_tokens: 321,
      response_format: { type: "json_schema", json_schema: { schema: SCHEMA } },
      temperature: 0.2, top_p: 0.9, stop_sequences: [ "END" ], metadata: { user_id: "test" })

    assert_equal "cloudflare-ai-gateway", response.provider
    assert_equal "gateway", response.api
    assert_equal "claude-haiku-5-5", client.model
    assert_equal({
      max_tokens: 321,
      thinking: { type: "adaptive" },
      output_config: { effort: "high", format: { type: "json_schema", schema: SCHEMA } },
      temperature: 0.2,
      top_p: 0.9,
      stop_sequences: [ "END" ],
      metadata: { user_id: "test" }
    }, client.options)
  end

  test "maps token limits for every upstream and preserves native max_tokens" do
    %w[openai/gpt-5.4-nano anthropic/claude-haiku-5.5 google/gemini-2.5-flash].each do |model|
      assert_equal({ model: model, max_tokens: 123 }, Mapper.map(model: model, max_completion_tokens: 123))
    end
    assert_equal({ max_tokens: 42 }, Mapper.map(max_tokens: 42))
    assert_raises(ArgumentError) { Mapper.map(max_tokens: 42, max_completion_tokens: 42) }
  end

  test "preserves upstream defaults and maps Anthropic reasoning controls" do
    assert_empty Mapper.map({})
    assert_empty Mapper.map(reasoning_control: { type: :none })
    assert_equal({ output_config: {} }, Mapper.map(response_format: "text"))
    assert_equal({ thinking: { type: "enabled", budget_tokens: 1024 } },
      Mapper.map(reasoning_control: { type: :budget_tokens, value: 1024 }))
    assert_equal({ thinking: { type: "adaptive" } }, Mapper.map(reasoning_control: { type: :toggle, value: true }))
    assert_raises(ArgumentError) { Mapper.map(response_format: "json_object") }
  end

  test "rejects unknown and OpenAI specific options" do
    %i[unknown_option cache_key cache_retention prompt_cache_retention store apiKey reasoning_effort stream_options seed].each do |option|
      error = assert_raises(ArgumentError) { Mapper.map(option => true) }
      assert_includes error.message, option.to_s
    end
  end

  test "does not handle transcript tools system or stream as options" do
    %i[messages tools system stream].each do |option|
      assert_raises(ArgumentError) { Mapper.map(option => []) }
    end
  end

  test "validates final output and leaves caller options unchanged" do
    options = {
      model: "openai/gpt-5.4-nano",
      max_completion_tokens: 12,
      response_format: "text",
      output_config: { effort: "low" },
      tool_choice: { type: "auto" },
      cache_control: { type: "ephemeral" }
    }
    original = Marshal.load(Marshal.dump(options))
    mapped = Mapper.map(options)
    assert_equal original, options
    assert_equal({ effort: "low" }, mapped[:output_config])
    assert_equal 12, mapped[:max_tokens]
    assert_empty mapped.keys - Mapper::VALID_OPTIONS
  end

  class FakeClient < LlmGateway::Clients::CloudflareAIGateway
    attr_reader :options, :model

    def initialize
      super(account_id: "a" * 32, api_key: "test-key")
    end

    def for_route(_route) = self

    def stream(_messages, tools:, system:, model:, **options)
      @options = options
      @model = model
      yield({ event: "message_start", data: { message: { id: "msg_cf", model: model, role: "assistant" } } })
      yield({ event: "message_delta", data: { delta: { stop_reason: "end_turn" } } })
      yield({ event: "message_stop", data: {} })
    end
  end
end
