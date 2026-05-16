# frozen_string_literal: true

require "test_helper"
require "vcr"
require_relative "../../utils/live_test_helper"

class StreamReasoningTest < Test
  include LiveTestHelper

  def teardown
    LlmGateway.reset_configuration!
  end

  def basic_thinking_test(adapter, reasoning: "high")
    prompt = "Think long and hard about 42 + 27"
    thinking_started = false
    thinking_chunks = ""
    thinking_completed = false
    response = adapter.stream(prompt, reasoning:,) do |event|
      case event.type
      when :reasoning_start
        thinking_started = true
        thinking_chunks += event.delta
      when :reasoning_delta
        thinking_chunks += event.delta
      when :reasoning_end
        thinking_completed = true
      end
    end

    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message
    assert_equal "stop", response.stop_reason, "Error: #{response.error_message}"

    if thinking_started || thinking_completed || !thinking_chunks.empty?
      assert_equal true, thinking_started, "thinking start event occurred"
      assert_operator thinking_chunks.length, :>, 0
      assert_equal true, thinking_completed, "thinking end event occurred"

      thinking_block = response.content.find { |block| block.type == "reasoning" }
      refute_nil thinking_block
      refute_empty thinking_block.reasoning.to_s
    else
      assert_operator response.usage[:reasoning_tokens], :>, 0
    end
  end

  def self.define_stream_reasoning_tests_for(provider:, model:)
    test "live_basic_thinking_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        basic_thinking_test(adapter, reasoning: "high")
      end
    end
  end

  define_stream_reasoning_tests_for(
    provider: "openai_apikey_completions",
    model: "gpt-5.1"
  )

  define_stream_reasoning_tests_for(
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_reasoning_tests_for(
    provider: "openai_apikey_responses",
    model: "gpt-5.4"
  )

  define_stream_reasoning_tests_for(
    provider: "anthropic_oauth_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_reasoning_tests_for(
    provider: "openai_oauth_codex",
    model: "gpt-5.4"
  )
end
