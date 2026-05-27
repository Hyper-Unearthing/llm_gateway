# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../utils/live_test_helper"

class HandoffStreamImageLiveTest < Test
  include LiveTestHelper

  SOURCE_TEST_PATH = File.expand_path("stream_image_test.rb", __dir__)
  FIXTURE_DIR = File.expand_path("../../fixtures/handoff/stream_image_test", __dir__)

  PAIRS = eval(File.read(SOURCE_TEST_PATH).match(/PAIRS = (\[.*?\])\s*\.freeze/m)[1])
              .reject { |pair| pair[:name] == "groq_completions" }
              .freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def run_handoff_stream_image_for(provider_name:, model:, adapter:, options: {})
    records = load_recorded_outputs
    transcript = [
      *recorded_messages(records),
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "how many times did you look at an image and what was its shape and color"
          }
        ]
      }
    ]

    response = adapter.stream(transcript, reasoning: "high", **options)
    refute_equal "error", response.stop_reason, "#{provider_name}/#{model} failed: #{response.error_message}"

    text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
    assert_includes text, "red"
    assert_includes text, "circle"
    expected_count = records.length.to_s
    arabic_indic_count = expected_count.tr("0-9", "٠-٩")
    assert text.include?(expected_count) || text.include?(arabic_indic_count), "Expected #{text.inspect} to include #{expected_count.inspect} or #{arabic_indic_count.inspect}"
  end

  def self.define_handoff_stream_image_test_for(provider_name:, provider:, model:, oauth:, options: {})
    test "handoff_stream_image__#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, oauth:) do |adapter|
        run_handoff_stream_image_for(provider_name:, model:, adapter:, options:)
      end
    end
  end

  PAIRS.each do |pair|
    define_handoff_stream_image_test_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end

  private

  def recorded_messages(records)
    records.flat_map do |record|
      deep_symbolize(record[:result])
    end
  end

  def load_recorded_outputs
    skip "Missing fixture directory at #{FIXTURE_DIR}. Run stream_image_test live tests first." unless Dir.exist?(FIXTURE_DIR)

    Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.map do |path|
      {
        pair: File.basename(path, ".json"),
        result: JSON.parse(File.read(path))
      }
    end.tap do |records|
      skip "No recorded outputs in #{FIXTURE_DIR}. Run stream_image_test live tests first." if records.empty?
    end
  end
end
