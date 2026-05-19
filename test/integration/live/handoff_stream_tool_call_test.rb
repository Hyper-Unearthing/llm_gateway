# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../utils/live_test_helper"

class HandoffStreamToolCallLiveTest < Test
  include LiveTestHelper

  SOURCE_TEST_PATH = File.expand_path("stream_tool_call_test.rb", __dir__)
  FIXTURE_DIR = File.expand_path("../../fixtures/handoff/stream_tool_call_test", __dir__)

  PAIRS = eval(File.read(SOURCE_TEST_PATH).match(/PAIRS = (\[.*?\])\s*\.freeze/m)[1]).freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def run_handoff_stream_for(provider:, model:, adapter:)
    records = load_recorded_outputs

    prompt = <<~PROMPT
      You are receiving recorded final outputs from previous streaming tool-call test runs.
      Read the JSON and answer in one short sentence. Include all of these facts as Arabic numerals
      where numeric: the number of recorded outputs and the tool-call sum 15 + 27.

      #{JSON.pretty_generate(records)}
    PROMPT

    response = adapter.stream(prompt, reasoning: "high")
    refute_equal "error", response.stop_reason, "#{provider}/#{model} failed: #{response.error_message}"

    text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
    assert_includes text, records.length.to_s
    assert_includes text, "42"
  end

  def self.define_handoff_stream_test_for(provider:, model:)
    test "handoff_stream_tool_call__#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        run_handoff_stream_for(provider:, model:, adapter:)
      end
    end
  end

  PAIRS.each do |pair|
    define_handoff_stream_test_for(provider: pair[:provider], model: pair[:model])
  end

  private

  def load_recorded_outputs
    skip "Missing fixture directory at #{FIXTURE_DIR}. Run stream_tool_call_test live tests first." unless Dir.exist?(FIXTURE_DIR)

    Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.map do |path|
      {
        pair: File.basename(path, ".json"),
        result: JSON.parse(File.read(path))
      }
    end.tap do |records|
      skip "No recorded outputs in #{FIXTURE_DIR}. Run stream_tool_call_test live tests first." if records.empty?
    end
  end
end
