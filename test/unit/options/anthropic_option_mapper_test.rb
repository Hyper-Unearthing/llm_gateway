# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class AnthropicOptionMapperTest < Test
  SCHEMA = { type: "object", properties: { outcome: { type: "string" } }, required: [ "outcome" ], additionalProperties: false }.freeze
  FORMAT = { type: "json_schema", json_schema: { name: "result", strict: true, schema: SCHEMA } }.freeze
  test "passes mapped managed options and provider-native options through adapter to client" do
    client = AnthropicOptionsFakeClient.new
    adapter = LlmGateway::Adapters::Anthropic::MessagesAdapter.new(client)

    adapter.stream(
      "hello",
      model: LlmGateway.models.fetch("anthropic/claude-sonnet-4-6"),
      max_completion_tokens: 321,
      reasoning: "high",
      response_format: FORMAT,
      container: "container_123",
      service_tier: "standard_only",
      stop_sequences: [ "END" ],
      top_k: 10,
      top_p: 0.9
    )

    assert_equal(
      {
        max_tokens: 321,
        thinking: { type: "adaptive" },
        output_config: { format: { type: "json_schema", schema: SCHEMA }, effort: "high" },
        container: "container_123",
        service_tier: "standard_only",
        stop_sequences: [ "END" ],
        top_k: 10,
        top_p: 0.9
      },
      client.options
    )
  end

  test "raises for unknown provider options" do
    error = assert_raises(ArgumentError) do
      LlmGateway::Adapters::AnthropicOptionMapper.map(unknown_option: true)
    end

    assert_includes error.message, "unknown_option"
  end

  test "does not handle transcript tools or system as options" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::AnthropicOptionMapper.map(messages: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::AnthropicOptionMapper.map(tools: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::AnthropicOptionMapper.map(system: "You are helpful")
    end
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(OptionMapperFixture.superset_options.merge(response_format: FORMAT))

    assert_equal(
      {
        max_tokens: 1234,
        cache_retention: "long",
        thinking: { type: "adaptive" },
        temperature: 0.2,
        output_config: { format: { type: "json_schema", schema: SCHEMA }, effort: "high" }
      },
      mapped
    )
  end

  test "preserves string-keyed schemas and native output settings" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(
      response_format: JSON.parse(JSON.generate(FORMAT)), output_config: { effort: "low" })
    assert_equal JSON.parse(JSON.generate(SCHEMA)), mapped.dig(:output_config, :format, :schema)
    assert_equal "low", mapped.dig(:output_config, :effort)
  end

  test "rejects schema-less JSON rather than silently discarding the contract" do
    [ "json_object", "json_schema", { type: "json_schema" } ].each do |format|
      assert_raises(ArgumentError) { LlmGateway::Adapters::AnthropicOptionMapper.map(response_format: format) }
    end
  end

  class AnthropicOptionsFakeClient < LlmGateway::Clients::Anthropic
    attr_reader :options

    def initialize
      super(api_key: "test-key")
    end

    def stream(_messages, tools:, system:, model: DEFAULT_MODEL, **options)
      @options = options
      yield({ event: "message_start", data: { message: { id: "msg_123", model: model, role: "assistant" } } })
      yield({ event: "message_delta", data: { delta: { stop_reason: "end_turn" } } })
      yield({ event: "message_stop", data: {} })
    end
  end
end
