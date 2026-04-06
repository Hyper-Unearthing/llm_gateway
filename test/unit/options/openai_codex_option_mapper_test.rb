# frozen_string_literal: true

require "test_helper"

class OpenAiCodexOptionMapperTest < Test
  test "keeps prompt_cache_key but removes retention fields" do
    mapped = LlmGateway::Adapters::OpenAiCodex::OptionMapper.map(
      cache_key: "abc",
      cache_retention: "long"
    )

    assert_equal "abc", mapped[:prompt_cache_key]
    refute mapped.key?(:prompt_cache_retention)
    refute mapped.key?(:cacheRetention)
    refute mapped.key?(:cache_retention)
  end

  test "removes token limit options" do
    mapped = LlmGateway::Adapters::OpenAiCodex::OptionMapper.map(max_completion_tokens: 999)

    refute mapped.key?(:max_output_tokens)
    refute mapped.key?(:max_completion_tokens)
  end

  test "inherits reasoning mapping from openai responses" do
    mapped = LlmGateway::Adapters::OpenAiCodex::OptionMapper.map(reasoning: "low")

    assert_equal({ effort: "low", summary: "detailed" }, mapped[:reasoning])
  end
end
