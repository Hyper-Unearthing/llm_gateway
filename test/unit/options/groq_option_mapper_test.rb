# frozen_string_literal: true

require "test_helper"
require_relative "option_mapper_fixture"

class GroqOptionMapperTest < Test
  test "sets defaults for temperature max_completion_tokens and response_format" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map({})

    assert_equal 0, mapped[:temperature]
    assert_equal 20_480, mapped[:max_completion_tokens]
    assert_equal({ type: "text" }, mapped[:response_format])
  end

  test "preserves explicit values" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(
      temperature: 0.3,
      max_completion_tokens: 123,
      response_format: { type: "json_object" }
    )

    assert_equal 0.3, mapped[:temperature]
    assert_equal 123, mapped[:max_completion_tokens]
    assert_equal({ type: "json_object" }, mapped[:response_format])
  end

  test "normalizes string response_format" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(response_format: "json_object")

    assert_equal({ type: "json_object" }, mapped[:response_format])
  end

  test "maps all supported options into final output" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(OptionMapperFixture.superset_options)

    assert_equal(
      {
        max_completion_tokens: 1234,
        cache_key: "abc",
        cache_retention: "long",
        reasoning: "high",
        temperature: 0.2,
        response_format: { type: "json_object" }
      },
      mapped
    )
  end
end
