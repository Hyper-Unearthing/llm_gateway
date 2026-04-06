# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class OpenAiChatCompletionsOptionMapperTest < Test
  test "sets default max_completion_tokens" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map({})

    assert_equal 20_480, mapped[:max_completion_tokens]
  end

  test "maps cache_key and short retention" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "short"
    )

    assert_equal "abc", mapped[:prompt_cache_key]
    assert_equal "in_memory", mapped[:prompt_cache_retention]
  end

  test "maps long retention" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "long"
    )

    assert_equal "abc", mapped[:prompt_cache_key]
    assert_equal "24h", mapped[:prompt_cache_retention]
  end

  test "none retention removes prompt cache key" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "none"
    )

    refute mapped.key?(:prompt_cache_key)
    refute mapped.key?(:prompt_cache_retention)
  end

  test "defaults retention to short when cache_key is present" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(cache_key: "abc")

    assert_equal "abc", mapped[:prompt_cache_key]
    assert_equal "in_memory", mapped[:prompt_cache_retention]
  end

  test "maps reasoning to reasoning_effort" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(reasoning: "high")

    assert_equal "high", mapped[:reasoning_effort]
    refute mapped.key?(:reasoning)
  end

  test "none reasoning is removed" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(reasoning: "none")

    refute mapped.key?(:reasoning)
    refute mapped.key?(:reasoning_effort)
  end

  test "raises for invalid reasoning" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(reasoning: "extreme")
    end
  end

  test "raises for invalid cache retention" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(cache_retention: "week")
    end
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::OpenAi::ChatCompletions::OptionMapper.map(OptionMapperFixture.superset_options)

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
end
