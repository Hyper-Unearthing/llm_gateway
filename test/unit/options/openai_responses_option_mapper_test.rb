# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class OpenAIResponsesOptionMapperTest < Test
  test "passes mapped managed options and provider-native options through adapter to client" do
    client = OpenAIResponsesOptionsFakeClient.new
    adapter = LlmGateway::Adapters::OpenAI::ResponsesAdapter.new(client)

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
        max_output_tokens: 321,
        prompt_cache_key: "cache_123",
        prompt_cache_retention: "24h",
        reasoning: { effort: "high", summary: "detailed" },
        text: { format: { type: "json_object" } },
        metadata: { request_id: "req_123" },
        service_tier: "auto",
        top_p: 0.9
      },
      client.options
    )
  end

  test "sets default max_output_tokens" do
    mapped = LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map({})

    assert_equal 20_480, mapped[:max_output_tokens]
  end

  test "none retention removes prompt cache key" do
    mapped = LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "none"
    )

    refute mapped.key?(:prompt_cache_key)
    refute mapped.key?(:prompt_cache_retention)
  end

  test "none reasoning is removed" do
    mapped = LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(reasoning: "none")

    refute mapped.key?(:reasoning)
  end

  test "raises for invalid reasoning" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(reasoning: "extreme")
    end
  end

  test "raises for invalid cache retention" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(cache_retention: "week")
    end
  end

  test "raises for unknown provider options" do
    error = assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(unknown_option: true)
    end

    assert_includes error.message, "unknown_option"
  end

  test "does not handle transcript tools or system as options" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(input: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(tools: [])
    end

    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(system: "You are helpful")
    end
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(OptionMapperFixture.superset_options)

    assert_equal(
      {
        max_output_tokens: 1234,
        prompt_cache_key: "abc",
        prompt_cache_retention: "24h",
        reasoning: { effort: "high", summary: "detailed" },
        temperature: 0.2,
        text: { format: { type: "json_object" } }
      },
      mapped
    )
  end

  class OpenAIResponsesOptionsFakeClient < LlmGateway::Clients::OpenAI
    attr_reader :options

    def initialize
      super(api_key: "test-key")
    end

    def stream_responses(_messages, tools:, system:, model: DEFAULT_MODEL, **options)
      @options = options
      yield({ event: "response.output_item.added", data: { output_index: 0, item: { type: "message", role: "assistant" } } })
      yield({ event: "response.content_part.added", data: { output_index: 0, part: { type: "output_text", text: "" } } })
      yield({ event: "response.output_text.delta", data: { output_index: 0, delta: "hi" } })
      yield({ event: "response.output_text.done", data: { output_index: 0, text: "hi" } })
      yield({ event: "response.completed", data: { response: { id: "resp_123", model: model, status: "completed", usage: {} } } })
    end
  end
end
