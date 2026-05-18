# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class OpenAIChatCompletionsOptionMapperTest < Test
  test "passes mapped managed options and provider-native options through adapter to client" do
    client = OpenAIChatCompletionsOptionsFakeClient.new
    adapter = LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter.new(client)

    adapter.stream(
      "hello",
      max_completion_tokens: 321,
      reasoning: "high",
      cache_key: "cache_123",
      cache_retention: "long",
      response_format: "json_object",
      metadata: { request_id: "req_123" },
      service_tier: "auto",
      top_p: 0.9
    )

    assert_equal(
      {
        max_completion_tokens: 321,
        prompt_cache_key: "cache_123",
        prompt_cache_retention: "24h",
        reasoning_effort: "high",
        response_format: "json_object",
        metadata: { request_id: "req_123" },
        service_tier: "auto",
        top_p: 0.9
      },
      client.options
    )
  end

  test "raises for unknown provider options" do
    error = assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(unknown_option: true)
    end

    assert_includes error.message, "unknown_option"
  end

  test "does not handle transcript tools or system as options" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(messages: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(tools: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(system: "You are helpful")
    end
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(OptionMapperFixture.superset_options)

    assert_equal(
      {
        max_completion_tokens: 1234,
        prompt_cache_key: "abc",
        prompt_cache_retention: "24h",
        reasoning_effort: "high",
        temperature: 0.2,
        response_format: "json_object"
      },
      mapped
    )
  end

  class OpenAIChatCompletionsOptionsFakeClient < LlmGateway::Clients::OpenAI
    attr_reader :options

    def initialize
      super(model_key: "gpt-4o", api_key: "test-key")
    end

    def stream(_messages, tools:, system:, **options)
      @options = options
      yield({ data: { id: "chatcmpl_123", model: model_key, choices: [ { delta: { role: "assistant" } } ] } })
      yield({ data: { choices: [ { delta: { content: "hi" } } ] } })
      yield({ data: { choices: [ { finish_reason: "stop" } ] } })
      yield({ data: { choices: [], usage: {} } })
    end
  end
end
