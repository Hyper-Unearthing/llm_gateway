# frozen_string_literal: true

require "test_helper"

class OpenAiResponsesOptionMapperTest < Test
  test "maps max_completion_tokens to max_output_tokens" do
    mapped = LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(max_completion_tokens: 777)

    assert_equal 777, mapped[:max_output_tokens]
    refute mapped.key?(:max_completion_tokens)
  end

  test "sets default max_output_tokens" do
    mapped = LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map({})

    assert_equal 20_480, mapped[:max_output_tokens]
  end

  test "maps cache_key and short retention" do
    mapped = LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "short"
    )

    assert_equal "abc", mapped[:prompt_cache_key]
    assert_equal "in_memory", mapped[:prompt_cache_retention]
  end

  test "none retention removes prompt cache key" do
    mapped = LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "none"
    )

    refute mapped.key?(:prompt_cache_key)
    refute mapped.key?(:prompt_cache_retention)
  end

  test "maps reasoning to reasoning hash" do
    mapped = LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(reasoning: "medium")

    assert_equal({ effort: "medium", summary: "detailed" }, mapped[:reasoning])
  end

  test "none reasoning is removed" do
    mapped = LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(reasoning: "none")

    refute mapped.key?(:reasoning)
  end

  test "raises for invalid reasoning" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(reasoning: "extreme")
    end
  end

  test "raises for invalid cache retention" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAi::Responses::OptionMapper.map(cache_retention: "week")
    end
  end
end
