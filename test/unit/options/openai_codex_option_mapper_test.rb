# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class OpenAICodexOptionMapperTest < Test
  test "keeps prompt_cache_key but removes retention fields" do
    mapped = LlmGateway::Adapters::OpenAICodex::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "long"
    )

    assert_equal "abc", mapped[:prompt_cache_key]
    refute mapped.key?(:prompt_cache_retention)
    refute mapped.key?(:cacheRetention)
    refute mapped.key?(:cache_retention)
  end

  test "removes token limit options" do
    mapped = LlmGateway::Adapters::OpenAICodex::OptionMapper.map(max_completion_tokens: 999)

    refute mapped.key?(:max_output_tokens)
    refute mapped.key?(:max_completion_tokens)
  end

  test "inherits reasoning mapping from openai responses" do
    mapped = LlmGateway::Adapters::OpenAICodex::OptionMapper.map(reasoning: "low")

    assert_equal({ effort: "low", summary: "detailed" }, mapped[:reasoning])
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::OpenAICodex::OptionMapper.map(OptionMapperFixture.superset_options)

    assert_equal(
      {
        prompt_cache_key: "abc",
        reasoning: { effort: "high", summary: "detailed" },
        temperature: 0.2,
        response_format: "json_object"
      },
      mapped
    )
  end
end
