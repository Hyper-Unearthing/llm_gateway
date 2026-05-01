# frozen_string_literal: true

require "test_helper"
require "json"

class InputMapperServerToolHistoryTest < Test
  test "anthropic maps normalized server tool result back to native result block type" do
    assistant_message = JSON.parse(
      File.read("test/fixtures/anthropic_stream/code_generation_expected.json"),
      symbolize_names: true
    )

    mapped = LlmGateway::Adapters::Anthropic::InputMapper.map(
      messages: [ assistant_message ],
      tools: nil,
      system: nil
    )

    first_tool_use = assistant_message[:content].find { |block| block[:type] == "server_tool_use" }
    first_tool_result = assistant_message[:content].find { |block| block[:type] == "server_tool_result" }

    mapped = mapped[:messages]

    assert_equal 1, mapped.length
    assert_equal "assistant", mapped.first[:role]

    mapped_content = mapped.first[:content]
    assert_includes mapped_content, first_tool_use
    assert_includes mapped_content, {
      type: first_tool_result[:name],
      tool_use_id: first_tool_result[:tool_use_id],
      content: first_tool_result[:content]
    }
    refute mapped_content.any? { |block| block[:type] == "server_tool_result" }
    refute mapped_content.any? { |block| block[:type] == first_tool_result[:name] && block.key?(:name) }
  end

  test "anthropic infers native result type when normalized result name is generic" do
    mapped = LlmGateway::Adapters::Anthropic::InputMapper.map(
      messages: [ {
        role: "assistant",
        content: [ {
          type: "server_tool_result",
          tool_use_id: "srvtoolu_123",
          name: "server_tool_result",
          content: { type: "bash_code_execution_result", stdout: "ok", stderr: "", return_code: 0 }
        } ]
      } ],
      tools: nil,
      system: nil
    )

    assert_equal "bash_code_execution_tool_result", mapped[:messages].first[:content].first[:type]
  end

  test "openai responses maps normalized server tool use back to native code interpreter call and drops result" do
    code = "import pandas as pd\nprint('/mnt/data/monthly_average_temperature.png')"

    assistant_message = {
      id: "resp_0534c2f5473481360069f1b897a8a081909a1fb9934c8711ad",
      model: "gpt-5.4-2026-03-05",
      role: "assistant",
      stop_reason: "tool_use",
      usage: {},
      content: [
        {
          type: "server_tool_use",
          id: "ci_0534c2f5473481360069f1b8986f308190a1c25220589f5682",
          name: "code_interpreter_call",
          input: {
            code: code,
            container_id: "cntr_69f1b897c20c8190bb237c6df29e44c40338ba4309faa269",
            outputs: nil
          }
        },
        { type: "text", text: "Done — the PNG chart has been created." },
        {
          type: "server_tool_result",
          tool_use_id: "ci_0534c2f5473481360069f1b8986f308190a1c25220589f5682",
          name: "server_tool_result",
          content: {
            container_id: "cntr_69f1b897c20c8190bb237c6df29e44c40338ba4309faa269",
            file_id: "cfile_69f1b8c2db48819183d58d4a15890914",
            filename: "monthly_average_temperature.png"
          }
        }
      ]
    }

    mapped = LlmGateway::Adapters::OpenAI::Responses::InputMapper.map_messages([ assistant_message ])

    assert_includes mapped, {
      id: "ci_0534c2f5473481360069f1b8986f308190a1c25220589f5682",
      type: "code_interpreter_call",
      status: "completed",
      code: code,
      container_id: "cntr_69f1b897c20c8190bb237c6df29e44c40338ba4309faa269",
      outputs: nil
    }

    assert_includes mapped, {
      role: "assistant",
      content: [ { type: "output_text", text: "Done — the PNG chart has been created." } ]
    }

    refute mapped.any? { |item| item[:type] == "server_tool_result" || item[:type] == "function_call_output" }
  end
end
