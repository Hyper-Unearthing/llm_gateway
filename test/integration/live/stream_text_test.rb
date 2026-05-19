# frozen_string_literal: true

require "test_helper"
require "vcr"
require_relative "../../utils/live_test_helper"

class StreamTextTest < Test
  include LiveTestHelper

  PAIRS = [
    { provider: "openai_apikey_completions", model: "gpt-5.1" },
    { provider: "anthropic_apikey_messages", model: "claude-sonnet-4-20250514" },
    { provider: "openai_apikey_responses", model: "gpt-5.4" },
    { provider: "anthropic_oauth_messages", model: "claude-sonnet-4-20250514" },
    { provider: "openai_oauth_codex", model: "gpt-5.4" }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def basic_streaming_text_test(adapter, options: {})
    text_started = false
    text_chunks = ""
    text_completed = false

    response = adapter.stream("Count from 1 to 3", **options) do |event|
      case event.type
      when :text_start
        text_started = true
        text_chunks += event.delta
      when :text_delta
        text_chunks += event.delta
      when :text_end
        text_completed = true
      end
    end

    assert_equal true, text_started, "text start event occurred"
    assert_operator text_chunks.length, :>, 0
    assert_equal true, text_completed, "text end event occurred"
    assert_equal "assistant", response.role
    assert response.content.any? { |block| block.type == "text" }

    response
  end

  def self.define_stream_tests_for(provider:, model:, options: {})
    test "live_text_streaming_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        response = basic_streaming_text_test(adapter, options: options)
        record_live_handoff_result(test_file: __FILE__, provider:, model:, result: response)
      end
    end
  end

  PAIRS.each do |pair|
    define_stream_tests_for(provider: pair[:provider], model: pair[:model], options: pair.fetch(:options, {}))
  end
end
