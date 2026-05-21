# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../utils/live_test_helper"

class HandoffStreamReasoningLiveTest < Test
  include LiveTestHelper

  SOURCE_TEST_PATH = File.expand_path("stream_reasoning_test.rb", __dir__)
  FIXTURE_DIR = File.expand_path("../../fixtures/handoff/stream_reasoning_test", __dir__)

  PAIRS = eval(File.read(SOURCE_TEST_PATH).match(/PAIRS = (\[.*?\])\s*\.freeze/m)[1]).freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def run_handoff_stream_reasoning_for(provider_name:, model:, adapter:, options: {})
    records = load_recorded_outputs

    prompt = <<~PROMPT
      You are receiving recorded final outputs from previous reasoning streaming tests.
      Each previous test asked the assistant to think about 42 + 27. Read the JSON and answer in one
      short sentence with the arithmetic result and the number of recorded outputs as Arabic numerals.

      #{JSON.pretty_generate(records)}
    PROMPT

    response = adapter.stream(prompt, reasoning: "high", **options)
    refute_equal "error", response.stop_reason, "#{provider_name}/#{model} failed: #{response.error_message}"

    text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
    assert_includes text, "69"
    assert_includes text, records.length.to_s
  end

  def self.define_handoff_stream_reasoning_test_for(provider_name:, provider:, model:, oauth:, options: {})
    test "handoff_stream_reasoning__#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, oauth:) do |adapter|
        run_handoff_stream_reasoning_for(provider_name:, model:, adapter:, options:)
      end
    end
  end

  PAIRS.each do |pair|
    define_handoff_stream_reasoning_test_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end

  private

  def load_recorded_outputs
    skip "Missing fixture directory at #{FIXTURE_DIR}. Run stream_reasoning_test live tests first." unless Dir.exist?(FIXTURE_DIR)

    Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.map do |path|
      {
        pair: File.basename(path, ".json"),
        result: JSON.parse(File.read(path))
      }
    end.tap do |records|
      skip "No recorded outputs in #{FIXTURE_DIR}. Run stream_reasoning_test live tests first." if records.empty?
    end
  end
end
