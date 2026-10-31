# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../utils/live_test_helper"

class HandoffStreamCodeGenerationSvgLiveTest < Test
  include LiveTestHelper

  SOURCE_TEST_PATH = File.expand_path("stream_code_generation_svg_test.rb", __dir__)
  FIXTURE_DIR = File.join(
    ENV["LLM_GATEWAY_LIVE_ARTIFACT_DIR"] || File.expand_path("../../fixtures", __dir__),
    "handoff/stream_code_generation_svg_test"
  )

  PAIRS = eval(File.read(SOURCE_TEST_PATH).match(/(?:PAIRS|PROVIDER_MODEL_PAIRS) = (\[.*?\])\s*\.freeze/m)[1]).freeze

  def teardown
  end

  def run_handoff_stream_for(provider:, model:, adapter:)
    records = load_recorded_outputs

    transcript = [
      *recorded_messages(records),
      {
        role: "user",
        content: [
          {
            type: "text",
            text: <<~PROMPT
              The earlier turns are archived chart-generation exchanges from different assistants.
              Use the recorded history only; do not run code, call tools, or create another file.
              Read the previous assistants' final replies about the saved filename and CSV row count.
              Report the PNG filename(s) and the original CSV data-row count they reported, not the number of plotted months.
              The original CSV includes the Annual Mean row and excludes the header from its data-row count.
              The same CSV repeats across exchanges; report its row count once, not the sum across exchanges.
              Reply in one short sentence, using digits for the row count.
            PROMPT
          }
        ]
      }
    ]

    response = adapter.stream(transcript, tools: handoff_tools_for(provider))
    refute_equal "error", response.stop_reason, "#{provider}/#{model} failed: #{response.error_message}"

    text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
    assert_includes text, "png"
    assert_match(/\b(13|14)\b/, text)
  end

  def self.define_handoff_stream_test_for(provider_name:, provider:, model:)
    test "handoff_stream_code_generation_svg__#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, redact_request_body: true) do |adapter|
        run_handoff_stream_for(provider:, model:, adapter:)
      end
    end
  end

  PAIRS.each do |pair|
    define_handoff_stream_test_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model])
  end

  private

  def recorded_messages(records)
    records.flat_map do |record|
      deep_symbolize(record[:result])
    end
  end

  def load_recorded_outputs
    skip "Missing fixture directory at #{FIXTURE_DIR}. Run stream_code_generation_svg_test live tests first." unless Dir.exist?(FIXTURE_DIR)

    Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.map do |path|
      {
        pair: File.basename(path, ".json"),
        result: JSON.parse(File.read(path))
      }
    end.tap do |records|
      skip "No recorded outputs in #{FIXTURE_DIR}. Run stream_code_generation_svg_test live tests first." if records.empty?
    end
  end

  def handoff_tools_for(provider)
    if provider == "openai-responses"
      [ openai_code_interpreter_tool ]
    else
      [ anthropic_code_execution_tool ]
    end
  end

  def openai_code_interpreter_tool
    {
      type: "code_interpreter",
      container: { type: "auto", memory_limit: "1g" }
    }
  end

  def anthropic_code_execution_tool
    {
      type: "code_execution_20250825",
      name: "code_execution"
    }
  end
end
