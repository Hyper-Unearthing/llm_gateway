# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/llm_gateway/adapters/openai/chat_completions/input_message_sanitizer"

class OpenAIChatCompletionsInputMessageSanitizerTest < Test
  SANITIZER = LlmGateway::Adapters::OpenAI::ChatCompletions::InputMessageSanitizer

  test "normalizes responses-style tool_use id and corresponding tool_result reference" do
    source_id = "call:abc/123|item_999"
    messages = [
      {
        role: "assistant",
        content: [ { type: "tool_use", id: source_id, name: "math", input: { a: 1 } } ]
      },
      {
        role: "developer",
        content: [ { type: "tool_result", tool_use_id: source_id, content: "ok" } ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "completions", target_model: "gpt-5.1")

    expected = "call_abc_123"
    assert_equal expected, result[0][:content][0][:id]
    assert_equal expected, result[1][:content][0][:tool_use_id]
  end

  test "truncates tool_use id to 40 chars when target provider is openai" do
    long_id = "x" * 60
    messages = [
      {
        role: "assistant",
        content: [ { type: "tool_use", id: long_id, name: "math", input: {} } ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "completions", target_model: "gpt-5.1")
    assert_equal 40, result[0][:content][0][:id].length
    assert_equal "x" * 40, result[0][:content][0][:id]
  end

  test "keeps tool_use id as-is for non-openai target provider when id has no pipe" do
    long_id = "z" * 60
    messages = [
      {
        role: "assistant",
        content: [ { type: "tool_use", id: long_id, name: "math", input: {} } ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "groq", target_api: "completions", target_model: "llama-3.3")
    assert_equal long_id, result[0][:content][0][:id]
  end
end
