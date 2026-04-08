# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/llm_gateway/adapters/input_message_sanitizer"

class InputMessageSanitizerTest < Test
  SANITIZER = LlmGateway::Adapters::InputMessageSanitizer

  test "keeps thinking/reasoning blocks for same provider api and model" do
    messages = [
      {
        role: "assistant",
        provider: "openai",
        api: "responses",
        model: "gpt-5.4",
        content: [ { type: "reasoning", reasoning: "private" } ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "responses", target_model: "gpt-5.4")
    assert_equal "reasoning", result[0][:content][0][:type]
  end

  test "flattens thinking/reasoning to text for cross provider/api/model" do
    messages = [
      {
        role: "assistant",
        provider: "anthropic",
        api: "messages",
        model: "claude-sonnet-4",
        content: [
          { type: "thinking", thinking: "first thought" },
          { type: "reasoning", summary: [ { text: "second thought" } ] }
        ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "responses", target_model: "gpt-5.4")

    assert_equal [ "text", "text" ], result[0][:content].map { |block| block[:type] }
    assert_equal [ "first thought", "second thought" ], result[0][:content].map { |block| block[:text] }
  end

  test "does not sanitize assistant reasoning when message metadata is missing" do
    messages = [
      {
        role: "assistant",
        content: [ { type: "reasoning", reasoning: "private" } ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "responses", target_model: "gpt-5.4")

    assert_equal "reasoning", result[0][:content][0][:type]
    assert_equal "private", result[0][:content][0][:reasoning]
  end
end
