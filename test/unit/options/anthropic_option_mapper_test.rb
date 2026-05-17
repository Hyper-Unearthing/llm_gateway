# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class AnthropicOptionMapperTest < Test
  test "passes mapped managed options and provider-native options through adapter to client" do
    client = AnthropicOptionsFakeClient.new
    adapter = LlmGateway::Adapters::Anthropic::MessagesAdapter.new(client)

    adapter.stream(
      "hello",
      max_completion_tokens: 321,
      reasoning: "high",
      response_format: "json_object",
      container: "container_123",
      service_tier: "standard_only",
      stop_sequences: [ "END" ],
      top_k: 10,
      top_p: 0.9
    )

    assert_equal(
      {
        max_tokens: 321,
        thinking: { type: "enabled", budget_tokens: 10_240 },
        output_config: { format: "json_schema" },
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
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(OptionMapperFixture.superset_options)

    assert_equal(
      {
        max_tokens: 1234,
        cache_retention: "long",
        thinking: { type: "enabled", budget_tokens: 10 * 1024 },
        temperature: 0.2,
        output_config: { format: "json_schema" }
      },
      mapped
    )
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
