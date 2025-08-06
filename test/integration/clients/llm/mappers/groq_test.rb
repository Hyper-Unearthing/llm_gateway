# frozen_string_literal: true

require "test_helper"

class GroqMapperTest < Minitest::Test
  test "groq mapper works" do
    input = {
      'id': "chatcmpl-3e519c7b-4d0c-456a-b752-e572d9174545",
      'object': "chat.completion",
      'created': 1_751_011_828,
      'model': "llama-3.3-70b-versatile",
      'choices': [ {
        'index': 0,
        'message': {
          'role': "assistant",
          'content': "Get the weather in Singapore right now please matey"
        },
        'logprobs': nil,
        'finish_reason': "stop"
      } ],
      'usage': {
        'queue_time': 0.05380553600000001,
        'prompt_tokens': 237,
        'prompt_time': 0.011981054,
        'completion_tokens': 11,
        'completion_time': 0.057935788,
        'total_tokens': 248,
        'total_time': 0.069916842
      },
      'usage_breakdown': nil,
      'system_fingerprint': "fp_6507bcfb6f",
      'x_groq': { 'id': "req_01jyr7095heq3vndantssq8kk7" }
    }

    output = {
      choices: [
        {
          content: [
            {
              text: "Get the weather in Singapore right now please matey",
              type: "text"
            }
          ]
        }
      ],
      usage: {
        queue_time: 0.05380553600000001,
        prompt_tokens: 237,
        prompt_time: 0.011981054,
        completion_tokens: 11,
        completion_time: 0.057935788,
        total_tokens: 248,
        total_time: 0.069916842
      },
      model: "llama-3.3-70b-versatile",
      id: "chatcmpl-3e519c7b-4d0c-456a-b752-e572d9174545"
    }
    result = LlmGateway::Adapters::Groq::OutputMapper.map(input)
    assert_equal output, result
  end

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
    result = LlmGateway::Adapters::Groq::InputMapper.map(input)

    assert_equal output, result[:messages]
  end
end
