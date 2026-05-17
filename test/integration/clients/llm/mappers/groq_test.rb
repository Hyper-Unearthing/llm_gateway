# frozen_string_literal: true

require "test_helper"

class GroqMapperTest < Test
  test "groq input mapper tool usage" do
    input = {
      messages: [
           { role: "assistant", content: [ { id: "call_tc9dHBkYgba7fDlJk6zk8Pr3", type: "tool_use", name: "Bash", input: { command: "find . -maxdepth 2 -type f -iname 'readme*'", timeout: 120000 } } ] },
           { role: "user", content: [ { type: "tool_result", tool_use_id: "call_tc9dHBkYgba7fDlJk6zk8Pr3", content: "./README.md\n" } ] }
          ]
    }

    output = [ {
      role: "assistant",
      content: nil,
      tool_calls: [ { id: "call_tc9dHBkYgba7fDlJk6zk8Pr3", type: "function", function: { name: "Bash", arguments: "{\"command\":\"find . -maxdepth 2 -type f -iname 'readme*'\",\"timeout\":120000}" } } ]
    },
     { role: "tool", tool_call_id: "call_tc9dHBkYgba7fDlJk6zk8Pr3", content: "./README.md\n"  } ]
    adapter = LlmGateway::Adapters::Groq::ChatCompletionsAdapter.new(Object.new)
    result = adapter.send(:map_input, input)

    assert_equal output, result[:messages]
  end
end
