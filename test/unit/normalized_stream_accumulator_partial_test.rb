# frozen_string_literal: true

require_relative "../test_helper"

class NormalizedStreamAccumulatorPartialTest < Test
  test "emitted events include accumulated partial assistant message" do
    accumulator = LlmGateway::Adapters::NormalizedStreamAccumulator.new(provider: "test-provider", api: "test-api")
    events = []

    [
      { type: :message_start, delta: { id: "msg_1", model: "test-model", role: "assistant" } },
      { type: :text_start, delta: "hel" },
      { type: :text_delta, delta: "lo" },
      { type: :message_delta, delta: { stop_reason: "stop" }, usage: { input: 3, output: 2 } },
      { type: :text_end },
      { type: :message_end }
    ].each do |patch|
      accumulator.push(patch) { |event| events << event }
    end

    assert(events[0...-1].all? { |event| event.partial.is_a?(PartialAssistantMessage) })
    assert_instance_of Integer, events[0].partial.timestamp
    assert(events[0...-1].all? { |event| event.partial.timestamp == events[0].partial.timestamp })
    assert_equal "msg_1", events[0].partial.id
    assert_equal "hel", events[1].partial.content[0].text
    assert_equal "hello", events[2].partial.content[0].text
    assert_equal "stop", events[3].partial.stop_reason
    refute_respond_to events[3].partial, :usage

    message_end = events.last
    assert(message_end.message.is_a?(AssistantMessage))
    refute_respond_to message_end, :partial
    assert_equal message_end.message, accumulator.final_message
    assert_equal "test-provider", message_end.message.provider
    assert_equal "test-api", message_end.message.api
    assert_equal events[0].partial.timestamp, message_end.message.timestamp
    assert_equal message_end.message.timestamp, message_end.message.to_h[:timestamp]
    assert_equal accumulator.result[:id], message_end.message.id
    assert_equal accumulator.result[:model], message_end.message.model
    assert_equal({ input: 3, cache_write: 0, cache_read: 0, output: 2, total: 5 }, message_end.message.usage)
    assert_equal accumulator.result[:usage], message_end.message.usage
    assert_equal accumulator.result[:stop_reason], message_end.message.stop_reason
    assert_equal accumulator.result[:content], message_end.message.content.map(&:to_h)
  end

  test "end events expose finalized block content directly" do
    accumulator = LlmGateway::Adapters::NormalizedStreamAccumulator.new
    events = []

    [
      { type: :text_start, delta: "hel" },
      { type: :text_delta, delta: "lo" },
      { type: :text_end },
      { type: :reasoning_start, delta: "think" },
      { type: :reasoning_delta, delta: "ing", signature: "sig" },
      { type: :reasoning_end },
      { type: :tool_start, id: "tool_1", name: "search" },
      { type: :tool_delta, delta: '{"query":"ruby"}' },
      { type: :tool_end }
    ].each do |patch|
      accumulator.push(patch) { |event| events << event }
    end

    text_end = events.find { |event| event.type == :text_end }
    assert_equal "hello", text_end.content
    assert_equal "hello", text_end.text
    assert_equal "hello", text_end.partial.content[text_end.content_index].text

    reasoning_end = events.find { |event| event.type == :reasoning_end }
    assert_equal "thinking", reasoning_end.content
    assert_equal "thinking", reasoning_end.reasoning
    assert_equal "thinking", reasoning_end.partial.content[reasoning_end.content_index].reasoning
    assert_equal "sig", reasoning_end.partial.content[reasoning_end.content_index].signature

    tool_end = events.find { |event| event.type == :tool_end }
    assert_equal tool_end.partial.content[tool_end.content_index], tool_end.content
    assert_equal tool_end.partial.content[tool_end.content_index], tool_end.tool_call
    assert_equal tool_end.tool_call, tool_end.tool
    assert_equal "tool_1", tool_end.tool_call.id
    assert_equal "search", tool_end.tool_call.name
    assert_equal({ query: "ruby" }, tool_end.tool_call.input)
  end

  test "accumulator preserves provider supplied timestamp" do
    accumulator = LlmGateway::Adapters::NormalizedStreamAccumulator.new(provider: "test-provider", api: "test-api")
    events = []

    [
      { type: :message_start, delta: { id: "msg_1", model: "test-model", role: "assistant", timestamp: 1_716_650_000_000 } },
      { type: :text_start, delta: "hello" },
      { type: :text_end },
      { type: :message_delta, delta: { stop_reason: "stop" } },
      { type: :message_end }
    ].each do |patch|
      accumulator.push(patch) { |event| events << event }
    end

    assert_equal 1_716_650_000_000, events.first.partial.timestamp
    assert_equal 1_716_650_000_000, events.last.message.timestamp
    assert_equal({ input: 0, cache_write: 0, cache_read: 0, output: 0, total: 0 }, events.last.message.usage)
  end

  test "usage is assigned from final usage patch rather than accumulated" do
    accumulator = LlmGateway::Adapters::NormalizedStreamAccumulator.new(provider: "test-provider", api: "test-api")
    events = []

    [
      { type: :message_start, delta: { id: "msg_1", model: "test-model", role: "assistant" }, usage: { input: 99 } },
      { type: :message_delta, delta: { stop_reason: "stop" }, usage: { input: 3, output: 2 } },
      { type: :message_end }
    ].each do |patch|
      accumulator.push(patch) { |event| events << event }
    end

    refute_respond_to events.first.partial, :usage
    assert_equal({ input: 3, cache_write: 0, cache_read: 0, output: 2, total: 5 }, events.last.message.usage)
  end

  test "usage total includes input cache and output tokens" do
    accumulator = LlmGateway::Adapters::NormalizedStreamAccumulator.new(provider: "test-provider", api: "test-api")
    events = []

    [
      { type: :message_start, delta: { id: "msg_1", model: "test-model", role: "assistant" } },
      { type: :message_delta, delta: { stop_reason: "stop" }, usage: { input: 3, cache_write: 4, cache_read: 5, output: 6, total: 999 } },
      { type: :message_end }
    ].each do |patch|
      accumulator.push(patch) { |event| events << event }
    end

    expected_usage = { input: 3, cache_write: 4, cache_read: 5, output: 6, total: 18 }
    assert_equal expected_usage, events[1].usage
    assert_equal expected_usage, events.last.message.usage
  end

  test "partial assistant message allows incomplete messages except timestamp but assistant message does not" do
    partial = PartialAssistantMessage.new(model: "test-model", timestamp: 1_716_650_000_000)

    assert_equal "test-model", partial.model
    assert_equal 1_716_650_000_000, partial.timestamp
    assert_raises(Dry::Struct::Error) { PartialAssistantMessage.new(model: "test-model") }
    assert_raises(Dry::Struct::Error) { AssistantMessage.new(model: "test-model", timestamp: 1_716_650_000_000) }
  end
end
