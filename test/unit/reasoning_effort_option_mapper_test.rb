# frozen_string_literal: true

require "test_helper"

class ReasoningEffortOptionMapperTest < Test
  UNION_LEVELS = %w[none default minimal low medium high xhigh max].freeze

  test "public managed reasoning API accepts the union of documented provider effort values" do
    assert_equal UNION_LEVELS, LlmGateway::Adapters::ReasoningEffortMapper::ACCEPTED_LEVELS

    UNION_LEVELS.each do |level|
      assert_equal level, LlmGateway::Adapters::ReasoningEffortMapper.normalize(level)
    end
  end

  test "OpenAI Chat Completions maps exact supported levels and falls back from max to xhigh" do
    mapped = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(reasoning: "minimal")
    assert_equal "minimal", mapped[:reasoning_effort]

    mapped = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(reasoning: "xhigh")
    assert_equal "xhigh", mapped[:reasoning_effort]

    mapped = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(reasoning: "max")
    assert_equal "xhigh", mapped[:reasoning_effort]
  end

  test "OpenAI Chat Completions applies documented model-specific fallbacks" do
    mapped = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(model: "gpt-5.1", reasoning: "minimal")
    assert_equal "low", mapped[:reasoning_effort]

    mapped = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(model: "gpt-5-pro", reasoning: "minimal")
    assert_equal "high", mapped[:reasoning_effort]
  end

  test "OpenAI Responses maps exact supported levels in reasoning object" do
    mapped = LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(reasoning: "minimal")
    assert_equal({ effort: "minimal", summary: "detailed" }, mapped[:reasoning])
  end

  test "OpenAI Responses applies documented model-specific fallbacks" do
    mapped = LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(model: "gpt-5.1", reasoning: "minimal")
    assert_equal({ effort: "low", summary: "detailed" }, mapped[:reasoning])
  end

  test "Anthropic maps minimal to closest supported low and max exactly" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(reasoning: "minimal")
    assert_equal({ effort: "low" }, mapped[:output_config])

    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(reasoning: "max")
    assert_equal({ effort: "max" }, mapped[:output_config])
  end

  test "Anthropic preserves response_format while adding managed effort to output_config" do
    mapped = LlmGateway::Adapters::AnthropicOptionMapper.map(
      response_format: "json_schema",
      reasoning: "xhigh"
    )

    assert_equal({ format: "json_schema", effort: "xhigh" }, mapped[:output_config])
  end

  test "Groq GPT-OSS maps minimal to closest supported low and xhigh/max to high" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(model: "openai/gpt-oss-120b", reasoning: "minimal")
    assert_equal "low", mapped[:reasoning_effort]
    assert_equal "parsed", mapped[:reasoning_format]

    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(model: "openai/gpt-oss-120b", reasoning: "xhigh")
    assert_equal "high", mapped[:reasoning_effort]

    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(model: "openai/gpt-oss-120b", reasoning: "max")
    assert_equal "high", mapped[:reasoning_effort]
  end

  test "Groq Qwen maps managed reasoning levels to default because docs only support default" do
    mapped = LlmGateway::Adapters::Groq::OptionMapper.map(model: "qwen/qwen3-32b", reasoning: "minimal")
    assert_equal "default", mapped[:reasoning_effort]
  end

  test "none preserves existing behavior and omits provider reasoning controls" do
    openai = LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(reasoning: "none")
    refute_includes openai.keys, :reasoning_effort

    anthropic = LlmGateway::Adapters::AnthropicOptionMapper.map(reasoning: "none")
    refute_includes anthropic.keys, :output_config

    groq = LlmGateway::Adapters::Groq::OptionMapper.map(reasoning: "none")
    refute_includes groq.keys, :reasoning_effort
    refute_includes groq.keys, :reasoning_format
  end

  test "invalid reasoning raises with the public union values" do
    error = assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses::OptionMapper.map(reasoning: "ultra")
    end

    assert_includes error.message, "minimal"
    assert_includes error.message, "max"
  end
end
