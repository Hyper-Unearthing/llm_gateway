# frozen_string_literal: true

require "test_helper"
require "vcr"
require_relative "../../utils/live_test_helper"

class StreamTextTest < Test
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

  def basic_streaming_text_test(adapter, options: {})
    text_started = false
    text_chunks = ""
    text_completed = false
    message_end_event = nil

    response = adapter.stream("Count from 1 to 3", **options) do |event|
      case event.type
      when :text_start
        text_started = true
        text_chunks += event.delta
      when :text_delta
        text_chunks += event.delta
      when :text_end
        text_completed = true
      when :message_end
        message_end_event = event
      end
    end

    assert_equal true, text_started, "text start event occurred"
    assert_operator text_chunks.length, :>, 0
    assert_equal true, text_completed, "text end event occurred"
    assert_stream_message_end_matches_response(message_end_event, response)
    assert_equal "assistant", response.role
    assert response.content.any? { |block| block.type == "text" }

    response
  end

  def self.define_stream_tests_for(provider_name:, provider:, model:, oauth:, options: {})
    test "live_text_streaming_#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, oauth:,) do |adapter|
        response = basic_streaming_text_test(adapter, options: options)
        record_live_handoff_result(test_file: __FILE__, provider: provider_name, model:, result: response)
      end
    end
  end

  PAIRS.each do |pair|
    define_stream_tests_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end
end
