# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../lib/llm_gateway/adapters/openai/chat_completions/stream_mapper"
require_relative "../../lib/llm_gateway/adapters/stream_accumulator"

OPENAI_STREAM_TEXT_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_stream/text_events.json", __dir__)), symbolize_names: true)
OPENAI_STREAM_TOOL_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_stream/tool_events.json", __dir__)), symbolize_names: true)
OPENAI_STREAM_REASONING_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/openai_stream/reasoning_events.json", __dir__)), symbolize_names: true)

class OpenAIStreamMapperTest < Test
  test "accumulates streamed text chunks" do
    mapper = LlmGateway::Adapters::OpenAI::ChatCompletions::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_STREAM_TEXT_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "chatcmpl-DN9U5IxtnhzRjwsqcxYGTxHTX2pxY",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "stop",
        usage: {
          input_tokens: 13,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 6,
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
    mapper = LlmGateway::Adapters::OpenAI::ChatCompletions::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_STREAM_TOOL_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "chatcmpl-DN9U65CkWOxg0z0e0eWmC8hWKbZYg",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "tool_use",
        usage: {
          input_tokens: 173,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 25,
          reasoning_tokens: 0
        },
        content: [
          {
            type: "tool_use",
            id: "call_LPi5Wn2BejjGjCj34X8qUWtq",
            name: "math_operation",
            input: { a: 15, b: 27, operation: "add" }
          }
        ]
      },
      accumulator.result
    )
  end

  test "accumulates streamed text when reasoning usage is present" do
    mapper = LlmGateway::Adapters::OpenAI::ChatCompletions::StreamMapper.new
    accumulator = StreamAccumulator.new

    OPENAI_STREAM_REASONING_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end

    assert_equal(
      {
        id: "chatcmpl-DN9U83mShrF9yOYECMUYEFfdnNHNH",
        model: "gpt-5.4-2026-03-05",
        role: "assistant",
        stop_reason: "stop",
        usage: {
          input_tokens: 21,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 123,
          reasoning_tokens: 74
        },
        content: [
          { type: "text", text: "44 + 27 = 71\n\nQuick check:\n- 40 + 20 = 60\n- 4 + 7 = 11\n- 60 + 11 = 71" }
        ]
      },
      accumulator.result
    )
  end
end
