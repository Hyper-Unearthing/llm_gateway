# frozen_string_literal: true

require_relative "../test_helper"

class NormalizedStreamAccumulatorPartialTest < Test
  test "emitted events include accumulated partial assistant message" do
    accumulator = LlmGateway::Adapters::NormalizedStreamAccumulator.new(provider: "test-provider", api: "test-api")
    events = []

    [
      { type: :message_start, delta: { id: "msg_1", model: "test-model", role: "assistant" }, usage_increment: { input_tokens: 3 } },
      { type: :text_start, delta: "hel" },
      { type: :text_delta, delta: "lo" },
      { type: :message_delta, delta: { stop_reason: "stop" }, usage_increment: { output_tokens: 2 } },
      { type: :text_end },
      { type: :message_end }
    ].each do |patch|
      accumulator.push(patch) { |event| events << event }
    end

    assert(events[0...-1].all? { |event| event.partial.is_a?(PartialAssistantMessage) })
    assert_equal "msg_1", events[0].partial.id
    assert_equal "hel", events[1].partial.content[0].text
    assert_equal "hello", events[2].partial.content[0].text
    assert_equal "stop", events[3].partial.stop_reason
    assert_equal 2, events[3].partial.usage[:output_tokens]

    message_end = events.last
    assert(message_end.message.is_a?(AssistantMessage))
    refute_respond_to message_end, :partial
    assert_equal message_end.message, accumulator.final_message
    assert_equal "test-provider", message_end.message.provider
    assert_equal "test-api", message_end.message.api
    assert_equal accumulator.result[:id], message_end.message.id
    assert_equal accumulator.result[:model], message_end.message.model
    assert_equal accumulator.result[:usage], message_end.message.usage
    assert_equal accumulator.result[:stop_reason], message_end.message.stop_reason
    assert_equal accumulator.result[:content], message_end.message.content.map(&:to_h)
  end

  test "partial assistant message allows incomplete messages but assistant message does not" do
    partial = PartialAssistantMessage.new(model: "test-model")

    assert_equal "test-model", partial.model
    assert_raises(Dry::Struct::Error) { AssistantMessage.new(model: "test-model") }
  end
end
