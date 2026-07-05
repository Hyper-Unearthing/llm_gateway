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
    assert_equal({ type: "tool_result", tool_use_id: "toolu_1", content: "ok" }, result.to_h)
  end

  test "tool call result serializes for transcript content" do
    result = LlmGateway::Agents::Event::ToolCallResult.new(
      tool_use_id: "toolu_1",
      content: 42
    )

    assert_equal({ type: "tool_result", tool_use_id: "toolu_1", content: 42 }, result.to_h)
    assert_equal 42, result.dig(:content)
  end
end
