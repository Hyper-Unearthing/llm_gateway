# frozen_string_literal: true

require "test_helper"
require "vcr"
require_relative "../../utils/live_test_helper"

class StreamReasoningTest < Test
  include LiveTestHelper

  PAIRS = [
    { name: "openai_apikey_completions", provider: "openai-completions", model: "gpt-6-luna" },
    # Haiku/Sonnet 5.5 stream empty thinking text; retain visible reasoning coverage.
    { name: "anthropic_apikey_messages", provider: "anthropic-messages", model: "claude-haiku-4-5-20251001" },
    { name: "openai_apikey_responses", provider: "openai-responses", model: "gpt-6-luna" },
    { name: "groq_completions", provider: "groq-completions", model: "openai/gpt-oss-20b", options: { temperature: 0.6 } }
  ].freeze

  def teardown
  end

  def basic_thinking_test(adapter, reasoning: "high", options: {})
    transcript = [ { role: "user", content: [ { type: "text", text: "Calculate 42 + 27. Think carefully about the addition, then give the final answer in one short sentence containing the expression and its result. Do not include alternative methods, number trivia, or unrelated calculations in the final answer." } ] } ]
    thinking_started = false
    thinking_chunks = ""
    thinking_completed = false
    message_end_event = nil
    response = adapter.stream(transcript, reasoning:, **options) do |event|
      case event.type
      when :reasoning_start
        thinking_started = true
        thinking_chunks += event.delta
      when :reasoning_delta
        thinking_chunks += event.delta
      when :reasoning_end
        thinking_completed = true
      when :message_end
        message_end_event = event
      end
    end

    assert_stream_message_end_matches_response(message_end_event, response)
    assert_equal "assistant", response.role
    assert_operator response.usage[:input], :>, 0
    assert_operator response.usage[:output], :>, 0
    assert_usage_costs(response)
    assert_nil response.error_message
    assert_equal "stop", response.stop_reason, "Error: #{response.error_message}"

    if thinking_started || thinking_completed || !thinking_chunks.empty?
      assert_equal true, thinking_started, "thinking start event occurred"
      assert_operator thinking_chunks.length, :>, 0
      assert_equal true, thinking_completed, "thinking end event occurred"

      thinking_block = response.content.find { |block| block.type == "reasoning" }
      refute_nil thinking_block
      refute_empty thinking_block.reasoning.to_s
    end

    transcript << response
    transcript
  end

  def self.define_stream_reasoning_tests_for(provider_name:, provider:, model:, options: {})
    test "live_basic_thinking_#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        transcript = basic_thinking_test(adapter, reasoning: "high", options: options)
        record_live_handoff_result(test_file: __FILE__, provider: provider_name, model:, result: transcript)
      end
    end
  end

  PAIRS.each do |pair|
    define_stream_reasoning_tests_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], options: pair.fetch(:options, {}))
  end
end
