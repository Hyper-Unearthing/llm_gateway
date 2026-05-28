# frozen_string_literal: true

require "test_helper"
require_relative "../../lib/llm_gateway/adapters/input_message_sanitizer"

class InputMessageSanitizerTest < Test
  SANITIZER = LlmGateway::Adapters::InputMessageSanitizer

  test "preserves provider-private blocks for compatible replay" do
    messages = [
      {
        role: "assistant",
        provider: "openai",
        api: "responses",
        model: "gpt-5.4",
        content: [
          { type: "reasoning", reasoning: "private" },
          { type: "server_tool_use", id: "srv_1", name: "code_interpreter_call", input: { code: "print(1)", outputs: {} } },
          { type: "server_tool_result", tool_use_id: "srv_1", content: { filename: "chart.png" } }
        ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "responses", target_model: "gpt-5.4")

    # Sanitized output keeps provider-private blocks intact for replay, while normalizing
    # server tool `outputs` from an empty hash to an empty array:
    # [
    #   {
    #     role: "assistant",
    #     provider: "openai",
    #     api: "responses",
    #     model: "gpt-5.4",
    #     content: [
    #       { type: "reasoning", reasoning: "private" },
    #       { type: "server_tool_use", id: "srv_1", name: "code_interpreter_call", input: { code: "print(1)", outputs: [] } },
    #       { type: "server_tool_result", tool_use_id: "srv_1", content: { filename: "chart.png" } }
    #     ]
    #   }
    # ]
    assert_equal [ "reasoning", "server_tool_use", "server_tool_result" ], result[0][:content].map { |block| block[:type] }
    assert_equal "private", result[0][:content][0][:reasoning]
    assert_equal [], result[0][:content][1][:input][:outputs]
  end

  test "sanitizes reasoning and server tool blocks for cross provider handoff" do
    messages = [
      {
        role: "assistant",
        provider: "anthropic",
        api: "messages",
        model: "claude-sonnet-4",
        content: [
          { type: "text", text: "I ran code" },
          { type: "thinking", thinking: "first thought" },
          { type: "reasoning", summary: [ { text: "second thought" } ] },
          { type: "server_tool_use", id: "srv_1", name: "bash_code_execution", input: { command: "python chart.py" } },
          { type: "server_tool_result", tool_use_id: "srv_1", content: { stdout: "chart.png" }, name: "bash_code_execution_tool_result" }
        ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "responses", target_model: "gpt-5.4")

    # Sanitized output converts private reasoning into text, converts server tools into
    # portable tool blocks, and moves the tool result into a following user message:
    # [
    #   {
    #     role: "assistant",
    #     provider: "anthropic",
    #     api: "messages",
    #     model: "claude-sonnet-4",
    #     content: [
    #       { type: "text", text: "I ran code" },
    #       { type: "text", text: "first thought" },
    #       { type: "text", text: "second thought" },
    #       { type: "tool_use", id: "srv_1", name: "bash_code_execution", input: { command: "python chart.py" } }
    #     ]
    #   },
    #   {
    #     role: "user",
    #     content: [
    #       { type: "tool_result", tool_use_id: "srv_1", content: "{\"stdout\":\"chart.png\"}", name: "bash_code_execution_tool_result" }
    #     ]
    #   }
    # ]
    assert_equal 2, result.length
    assert_equal "assistant", result[0][:role]
    assert_equal [ "text", "text", "text", "tool_use" ], result[0][:content].map { |block| block[:type] }
    assert_equal [ "I ran code", "first thought", "second thought" ], result[0][:content].first(3).map { |block| block[:text] }
    assert_equal({ type: "tool_use", id: "srv_1", name: "bash_code_execution", input: { command: "python chart.py" } }, result[0][:content][3])

    assert_equal "user", result[1][:role]
    assert_equal [ "tool_result" ], result[1][:content].map { |block| block[:type] }
    assert_equal "srv_1", result[1][:content][0][:tool_use_id]
    assert_equal '{"stdout":"chart.png"}', result[1][:content][0][:content]
  end

  test "leaves assistant private blocks untouched when metadata is missing" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "reasoning", reasoning: "private" },
          { type: "server_tool_use", id: "srv_1", name: "code_interpreter_call", input: { code: "print(1)" } }
        ]
      }
    ]

    result = SANITIZER.sanitize(messages, target_provider: "openai", target_api: "responses", target_model: "gpt-5.4")

    # Sanitized output is unchanged because sanitizer only rewrites assistant messages
    # when provider/api/model metadata is present:
    # [
    #   {
    #     role: "assistant",
    #     content: [
    #       { type: "reasoning", reasoning: "private" },
    #       { type: "server_tool_use", id: "srv_1", name: "code_interpreter_call", input: { code: "print(1)" } }
    #     ]
    #   }
    # ]
    assert_equal messages, result
  end
end
