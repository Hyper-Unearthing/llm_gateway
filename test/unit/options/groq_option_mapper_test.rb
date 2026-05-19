# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class GroqOptionMapperTest < Test
  test "passes mapped managed options and provider-native options through adapter to client" do
    client = GroqOptionsFakeClient.new
    adapter = LlmGateway::Adapters::Groq::ChatCompletionsAdapter.new(client)

    adapter.stream(
      "hello",
      max_completion_tokens: 321,
      reasoning: "high",
      cache_key: "cache_123",
      cache_retention: "long",
      response_format: "json_object",
      citation_options: "enabled",
      service_tier: "auto",
      top_p: 0.9
    )

    assert_equal(
      {
        max_completion_tokens: 321,
        response_format: { type: "json_object" },
        citation_options: "enabled",
        service_tier: "auto",
        top_p: 0.9,
        temperature: 0,
        reasoning_effort: "high",
        reasoning_format: "parsed"
      },
      client.options
    )
  end

  test "sets defaults for temperature max_completion_tokens and response_format" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map({})

    assert_equal 0, mapped[:temperature]
    assert_equal 20_480, mapped[:max_completion_tokens]
    assert_equal({ type: "text" }, mapped[:response_format])
  end

  test "raises for unknown provider options" do
    error = assert_raises(ArgumentError) do
      LlmGateway::Adapters::Groq::OptionMapper.map(unknown_option: true)
    end

    assert_includes error.message, "unknown_option"
  end

  test "does not handle transcript tools or system as options" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::Groq::OptionMapper.map(messages: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::Groq::OptionMapper.map(tools: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::Groq::OptionMapper.map(system: "You are helpful")
    end
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(OptionMapperFixture.superset_options)

    assert_equal(
      {
        max_completion_tokens: 1234,
        temperature: 0.2,
        response_format: { type: "json_object" },
        reasoning_effort: "high",
        reasoning_format: "parsed"
      },
      mapped
    )
  end

  class GroqOptionsFakeClient < LlmGateway::Clients::Groq
    attr_reader :options

    def initialize
      super(model_key: "openai/gpt-oss-120b", api_key: "test-key")
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
