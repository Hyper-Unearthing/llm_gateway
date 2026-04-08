# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../lib/llm_gateway/adapters/openai/responses/stream_mapper"
require_relative "../../lib/llm_gateway/adapters/stream_accumulator"

OPENAI_CODEX_STREAM_TEXT_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_codex_stream/text_events.json", __dir__)), symbolize_names: true)
OPENAI_CODEX_STREAM_TOOL_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_codex_stream/tool_events.json", __dir__)), symbolize_names: true)
OPENAI_CODEX_STREAM_REASONING_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_codex_stream/reasoning_events.json", __dir__)), symbolize_names: true)

# Pull the canonical reasoning text from the fixture's done event so we don't
# have to worry about Unicode apostrophes or other subtle character differences.
OPENAI_CODEX_REASONING_TEXT = OPENAI_CODEX_STREAM_REASONING_EVENTS_FIXTURE
  .find { |e| e[:event] == "response.reasoning_summary_text.done" }
  .dig(:data, :text)

class OpenAICodexStreamMapperTest < Test
  test "accumulates streamed text chunks" do
    mapper = LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_CODEX_STREAM_TEXT_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_04e30538c4f63fda0169c4a6cb94ac819188fc1d1328f92ec6",
        model: "gpt-5.4",
        role: "assistant",
        stop_reason: "stop",
        usage: {
          input_tokens: 23,
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

    OPENAI_CODEX_STREAM_TOOL_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_0f79381ce0eb24d30169c4a6ccbcc88191abe5e6212ee6ea52",
        model: "gpt-5.4",
        role: "assistant",
        stop_reason: "tool_use",
        usage: {
          input_tokens: 101,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 26,
          reasoning_tokens: 0
        },
        content: [
          {
            type: "tool_use",
            id: "call_BPwa87gLbdmLhFQPLIpKLnwo",
            name: "math_operation",
            input: { a: 15, b: 27, operation: "add" }
          }
        ]
      },
      accumulator.result
    )
  end

  test "accumulates streamed reasoning summary and text chunks" do
    mapper = LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_CODEX_STREAM_REASONING_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "resp_0f0b432c05cf59a90169c4a6ce0838819187d9ebaecf947c17",
        model: "gpt-5.4",
        role: "assistant",
        stop_reason: "stop",
        usage: {
          input_tokens: 31,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 127,
          reasoning_tokens: 86
        },
        content: [
          {
            type: "reasoning",
            reasoning: OPENAI_CODEX_REASONING_TEXT,
            signature: ""
          },
          { type: "text", text: "44 + 27 = 71\n\nQuick way:\n- 44 + 20 = 64\n- 64 + 7 = 71\n\nAnswer: 71" }
        ]
      },
      accumulator.result
    )
  end
end
