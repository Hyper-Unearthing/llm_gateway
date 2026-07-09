# frozen_string_literal: true

require_relative "../test_helper"

class ToolCallResultTest < Test
  class EchoTool < LlmGateway::Tool
    def execute(input, tool_use_id:)
      tool_result(input[:value], tool_use_id: tool_use_id)
    end
  end

  test "tool helper returns a tool call result" do
    result = EchoTool.new.execute({ value: "ok" }, tool_use_id: "toolu_1")

    assert_instance_of LlmGateway::Agents::Event::ToolCallResult, result
    assert_equal "ok", result.content
    assert_equal({ type: "tool_result", tool_use_id: "toolu_1", content: "ok", is_error: false }, result.to_h)
  end

  test "tool call result serializes for transcript content" do
    result = LlmGateway::Agents::Event::ToolCallResult.new(
      tool_use_id: "toolu_1",
      content: 42
    )

    assert_equal({ type: "tool_result", tool_use_id: "toolu_1", content: 42, is_error: false }, result.to_h)
    assert_equal 42, result.dig(:content)
  end

  test "tool call result can indicate an error" do
    result = LlmGateway::Agents::Event::ToolCallResult.new(
      tool_use_id: "toolu_1",
      content: "failed",
      is_error: true
    )

    assert_equal true, result.is_error
    assert_equal({ type: "tool_result", tool_use_id: "toolu_1", content: "failed", is_error: true }, result.to_h)
  end
end
