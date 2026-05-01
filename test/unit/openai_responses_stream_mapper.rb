# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../lib/llm_gateway/adapters/openai/responses/stream_mapper"
require_relative "../../lib/llm_gateway/adapters/stream_accumulator"

OPENAI_RESPONSES_STREAM_TEXT_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_responses_stream/text_events.json", __dir__)), symbolize_names: true)
OPENAI_RESPONSES_STREAM_TOOL_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_responses_stream/tool_events.json", __dir__)), symbolize_names: true)
OPENAI_RESPONSES_STREAM_REASONING_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_responses_stream/reasoning_events.json", __dir__)), symbolize_names: true)
OPENAI_RESPONSES_STREAM_CODE_GENERATION_TOOL_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_responses_stream/code_generation_tool_events.json", __dir__)), symbolize_names: true)

class OpenAIResponsesStreamMapperTest < Test
  test "accumulates streamed text chunks" do
    mapper = LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_RESPONSES_STREAM_TEXT_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_08f447bf54416f500069c35a4d68108197a3ad5516f7662d23",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "stop",
        usage: {
          input_tokens: 13,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 7,
          reasoning_tokens: 0
        },
        content: [
          { type: "text", text: "Hello test successful" }
        ]
      },
      accumulator.result
    )
  end

  test "accumulates streamed tool call chunks" do
    mapper = LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_RESPONSES_STREAM_TOOL_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_0b759307391e7bcd0069c35a4fccd88194b84d10e8735c2717",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "tool_use",
        usage: {
          input_tokens: 91,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 26,
          reasoning_tokens: 0
        },
        content: [
          {
            type: "tool_use",
            id: "call_9XROhpAoJYWHd7tdKlIH2H2N",
            name: "math_operation",
            input: { a: 15, b: 27, operation: "add" }
          }
        ]
      },
      accumulator.result
    )
  end

  test "accumulates streamed text when reasoning usage is present" do
    mapper = LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_RESPONSES_STREAM_REASONING_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_0e40f508774b4eb80069c35a515a5c819093f8d74568de7f7a",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "stop",
        usage: {
          input_tokens: 21,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 127,
          reasoning_tokens: 86
        },
        content: [
          {
            type: "reasoning",
            reasoning: "**Calculating arithmetic clearly**\n\nI need to answer the user's question about 44 + 27 step by step, but I should keep my reasoning concise. I think I can show briefly how I got the answer: starting with 44, adding 20 to get 64, and then adding 7 to reach 71. So, I’ll just present the final answer clearly: 44 + 27 = 71. That should work well for the user!",
            signature: ""
          },
          { type: "text", text: "44 + 27 = 71\n\nQuick steps:\n- 44 + 20 = 64\n- 64 + 7 = 71\n\nAnswer: 71" }
        ]
      },
      accumulator.result
    )
  end

  test "maps code generation tool stream fixture" do
    mapper = LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_RESPONSES_STREAM_CODE_GENERATION_TOOL_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_0534c2f5473481360069f1b897a8a081909a1fb9934c8711ad",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "tool_use",
        usage: {
          input_tokens: 1755,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 1280,
          output_tokens: 329,
          reasoning_tokens: 0
        },
        content: [
          {
            type: "server_tool_use",
            id: "ci_0534c2f5473481360069f1b8986f308190a1c25220589f5682",
            name: "code_interpreter_call",
            input: {
              code: "import pandas as pd\nimport matplotlib.pyplot as plt\nfrom io import StringIO\n\ncsv_data = \"\"\"Month,Average Temperature (°C),Deviation from 1991-2020 Norm (°C)\nJanuary,0.0,+1.5\nFebruary,1.3,+1.7\nMarch,4.1,+1.5\nApril,8.2,+1.9\nMay,10.3,-0.2\nJune,17.6,+3.8\nJuly,15.4,-0.3\nAugust,16.4,+1.2\nSeptember,11.9,+0.5\nOctober,7.2,-0.2\nNovember,2.3,+0.1\nDecember,1.3,+2.0\nAnnual Mean,8.0,+1.1\n\"\"\"\n\ndf = pd.read_csv(StringIO(csv_data))\ndf = df[df[\"Month\"] != \"Annual Mean\"]\n\nplt.figure(figsize=(10, 5))\nplt.plot(df[\"Month\"], df[\"Average Temperature (°C)\"], marker='o', linewidth=2)\nplt.xlabel(\"Month\")\nplt.ylabel(\"Average Temperature (°C)\")\nplt.title(\"Monthly Average Temperature\")\nplt.xticks(rotation=45)\nplt.tight_layout()\n\noutput_path = \"/mnt/data/monthly_average_temperature.png\"\nplt.savefig(output_path, dpi=200)\nplt.close()\n\nprint(output_path)",
              container_id: "cntr_69f1b897c20c8190bb237c6df29e44c40338ba4309faa269",
              outputs: nil
            }
          },
          { type: "text", text: "Done — the PNG chart has been created.\n\n[Download the PNG chart](sandbox:/mnt/data/monthly_average_temperature.png)" },
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
      },
      accumulator.result
    )
  end
end
