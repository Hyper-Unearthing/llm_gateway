# frozen_string_literal: true

require "test_helper"
require_relative "../../utils/live_test_helper"

class PromptTooLongLiveTest < Test
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

  def huge_prompt
    "Please reply with one short sentence.\n\n" + ("lorem ipsum dolor sit amet " * 240_000)
  end

  def assert_prompt_too_long(adapter, provider, options: {})
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      adapter.stream(huge_prompt, **options)
    end

    assert LlmGateway::Errors.context_overflow_message?(error.message),
      "Expected prompt-length related error message for #{provider}, got: #{error.message}"
  end

  def self.define_prompt_too_long_debug_test(provider:, model:, options: {})
    test "live_prompt_too_long_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:, redact_request_body: true) do |adapter|
        assert_prompt_too_long(adapter, provider, options: options)
      end
    end
  end

  PAIRS.each do |pair|
    define_prompt_too_long_debug_test(provider: pair[:provider], model: pair[:model], options: pair.fetch(:options, {}))
  end
end
