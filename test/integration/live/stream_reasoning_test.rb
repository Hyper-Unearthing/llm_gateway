# frozen_string_literal: true

require "test_helper"
require "vcr"
require_relative "../../utils/live_test_helper"

class StreamReasoningTest < Test
  include LiveTestHelper

  PAIRS = [
    { name: "openai_apikey_completions", provider: "openai_completions", model: "gpt-5.1" },
    { name: "anthropic_apikey_messages", provider: "anthropic_messages", model: "claude-sonnet-4-20250514" },
    { name: "openai_apikey_responses", provider: "openai_responses", model: "gpt-5.4" },
    { name: "anthropic_oauth_messages", provider: "anthropic_messages", model: "claude-sonnet-4-20250514", oauth: true },
    { name: "openai_oauth_codex", provider: "openai_codex", model: "gpt-5.4" },
    { name: "groq_completions", provider: "groq_completions", model: "openai/gpt-oss-120b" }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def basic_thinking_test(adapter, reasoning: "high", options: {})
    prompt = "Think long and hard about 42 + 27"
    thinking_started = false
    thinking_chunks = ""
    thinking_completed = false
    message_end_event = nil
    response = adapter.stream(prompt, reasoning:, **options) do |event|
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

    response
  end

  def self.define_stream_reasoning_tests_for(provider_name:, provider:, model:, oauth:, options: {})
    test "live_basic_thinking_#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, oauth:,) do |adapter|
        response = basic_thinking_test(adapter, reasoning: "high", options: options)
        record_live_handoff_result(test_file: __FILE__, provider: provider_name, model:, result: response)
      end
    end
  end

  PAIRS.each do |pair|
    define_stream_reasoning_tests_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end
end
