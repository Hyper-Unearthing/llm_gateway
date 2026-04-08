# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../utils/live_test_helper"
require_relative "../utils/calculator_tool_helper"

class HandoffLiveTest < Test
  include LiveTestHelper
  include CalculatorToolHelper

  FIXTURE_PATH = File.expand_path("../fixtures/handoff_live_fixture.json", __dir__)

  PAIRS = [
    { provider: "openai_apikey_completions", model: "gpt-5.1" },
    { provider: "openai_apikey_responses", model: "gpt-5.4" },
    { provider: "openai_oauth_codex", model: "gpt-5.4" },
    { provider: "anthropic_apikey_messages", model: "claude-sonnet-4-20250514" }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def run_handoff_for(provider:, model:)
    skip "Missing fixture at #{FIXTURE_PATH}. Run: ruby scripts/generate_handoff_live_fixture.rb" unless File.exist?(FIXTURE_PATH)

    base_transcript = symbolize(JSON.parse(File.read(FIXTURE_PATH)))
    transcript = Marshal.load(Marshal.dump(base_transcript))
    transcript << { role: "user", content: "How many tool calls have you made" }

    adapter = load_provider(provider:, model:)
    response = adapter.stream(transcript, tools: [ math_operation_tool ], reasoning: "high")
    refute_equal "error", response.stop_reason, "#{provider}/#{model} failed: #{response.error_message}"

    has_text_with_four = response.content.any? do |block|
      block.type == "text" && block.text.include?(PAIRS.length.to_s)
    end
    assert has_text_with_four, "#{provider}/#{model} expected a text block containing '4', got: #{response.content.map(&:to_h)}"
  end

  def self.define_handoff_test_for(provider:, model:)
    test "#{provider}_#{model} handoff_live_test" do
      skip_on_authentication_error do
        without_vcr do
          run_handoff_for(provider:, model:)
        end
      end
    end
  end

  PAIRS.each do |pair|
    define_handoff_test_for(provider: pair[:provider], model: pair[:model])
  end

  private

  def symbolize(value)
    case value
    when Array
      value.map { |item| symbolize(item) }
    when Hash
      value.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = symbolize(v) }
    else
      value
    end
  end
end
