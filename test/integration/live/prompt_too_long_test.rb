# frozen_string_literal: true

require "test_helper"
require_relative "../../utils/live_test_helper"

class PromptTooLongLiveTest < Test
  include LiveTestHelper

  def teardown
    LlmGateway.reset_configuration!
  end

  def huge_prompt
    "Please reply with one short sentence.\n\n" + ("lorem ipsum dolor sit amet " * 240_000)
  end

  def assert_prompt_too_long(adapter, provider)
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      adapter.stream(huge_prompt)
    end

    assert LlmGateway::Errors.context_overflow_message?(error.message),
      "Expected prompt-length related error message for #{provider}, got: #{error.message}"
  end

  def self.define_prompt_too_long_debug_test(provider:, model:)
    test "live_prompt_too_long_#{provider}_#{model}" do
      without_vcr do
        adapter = load_provider(provider:, model:)
        assert_prompt_too_long(adapter, provider)
      end
    end
  end

  define_prompt_too_long_debug_test(
    provider: "openai_apikey_completions",
    model: "gpt-5.1"
  )

  define_prompt_too_long_debug_test(
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_prompt_too_long_debug_test(
    provider: "openai_apikey_responses",
    model: "gpt-5.4"
  )

  define_prompt_too_long_debug_test(
    provider: "anthropic_oauth_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_prompt_too_long_debug_test(
    provider: "openai_oauth_codex",
    model: "gpt-5.4"
  )
end
