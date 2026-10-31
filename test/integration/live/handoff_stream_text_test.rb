# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../utils/live_test_helper"

class HandoffStreamTextLiveTest < Test
  include LiveTestHelper

  SOURCE_TEST_PATH = File.expand_path("stream_text_test.rb", __dir__)
  FIXTURE_DIR = File.join(
    ENV["LLM_GATEWAY_LIVE_ARTIFACT_DIR"] || File.expand_path("../../fixtures", __dir__),
    "handoff/stream_text_test"
  )

  PAIRS = eval(File.read(SOURCE_TEST_PATH).match(/PAIRS = (\[.*?\])\s*\.freeze/m)[1]).freeze

  def teardown
  end

  def run_handoff_stream_for(provider_name:, model:, adapter:, options: {})
    records = load_recorded_outputs

    transcript = [
      *recorded_messages(records),
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "how many times did you count from 1 to 3."
          }
        ]
      }
    ]

    reasoning_options = adapter.model.supports_reasoning? ? { reasoning: "high" } : {}
    response = adapter.stream(transcript, **reasoning_options, **options)
    refute_equal "error", response.stop_reason, "#{provider_name}/#{model} failed: #{response.error_message}"

    text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
    expected_count = records.length
    expected_word = %w[zero one two three four five six seven eight nine ten][expected_count]
    assert_match(/\b(#{expected_count}|#{expected_word || expected_count})\b/, text)
  end

  def self.define_handoff_stream_test_for(provider_name:, provider:, model:, oauth:, options: {})
    test "handoff_stream_text__#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, oauth:) do |adapter|
        run_handoff_stream_for(provider_name:, model:, adapter:, options:)
      end
    end
  end

  PAIRS.each do |pair|
    define_handoff_stream_test_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end

  private

  def recorded_messages(records)
    records.flat_map do |record|
      deep_symbolize(record[:result])
    end
  end

  def load_recorded_outputs
    skip "Missing fixture directory at #{FIXTURE_DIR}. Run stream_text_test live tests first." unless Dir.exist?(FIXTURE_DIR)

    Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.map do |path|
      {
        pair: File.basename(path, ".json"),
        result: JSON.parse(File.read(path))
      }
    end.tap do |records|
      skip "No recorded outputs in #{FIXTURE_DIR}. Run stream_text_test live tests first." if records.empty?
    end
  end
end
