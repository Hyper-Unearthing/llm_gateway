# frozen_string_literal: true

require "test_helper"
require_relative "../../utils/live_test_helper"

class PromptTooLongLiveTest < Test
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

  def self.define_prompt_too_long_debug_test(provider_name:, provider:, model:, oauth:, options: {})
    test "live_prompt_too_long_#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, redact_request_body: true, oauth:,) do |adapter|
        assert_prompt_too_long(adapter, provider_name, options: options)
      end
    end
  end

  PAIRS.each do |pair|
    define_prompt_too_long_debug_test(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end
end
