# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class AnthropicOptionMapperTest < Test
  test "maps max_completion_tokens to max_tokens" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(max_completion_tokens: 321)

    assert_equal 321, mapped[:max_tokens]
    refute mapped.key?(:max_completion_tokens)
  end

  test "sets default max_tokens" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map({})

    assert_equal 20_480, mapped[:max_tokens]
  end

  test "forwards cache_retention as is" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(cache_retention: "long")

    assert_equal "long", mapped[:cache_retention]
    refute mapped.key?(:prompt_cache_retention)
  end

  test "forwards none cache_retention" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(cache_retention: "none")

    assert_equal "none", mapped[:cache_retention]
  end

  test "maps reasoning to thinking with budget tokens" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(reasoning: "high")

    assert_equal({ type: "enabled", budget_tokens: 10_240 }, mapped[:thinking])
    refute mapped.key?(:reasoning)
  end

  test "none reasoning is removed" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(reasoning: "none")

    refute mapped.key?(:thinking)
    refute mapped.key?(:reasoning)
  end

  test "raises for invalid reasoning" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::AnthropicOptionMapper.map(reasoning: "extreme")
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
end
