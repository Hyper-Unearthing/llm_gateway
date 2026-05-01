# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../utils/live_test_helper"

class CodeGenerationPngLiveTest < Test
  include LiveTestHelper

  CSV_DATA = <<~CSV.freeze
    Month,Average Temperature (°C),Deviation from 1991-2020 Norm (°C)
    January,0.0,+1.5
    February,1.3,+1.7
    March,4.1,+1.5
    April,8.2,+1.9
    May,10.3,-0.2
    June,17.6,+3.8
    July,15.4,-0.3
    August,16.4,+1.2
    September,11.9,+0.5
    October,7.2,-0.2
    November,2.3,+0.1
    December,1.3,+2.0
    Annual Mean,8.0,+1.1
  CSV

  PROVIDER_MODEL_PAIRS = [
    { provider: "anthropic_apikey_messages", model: "claude-sonnet-4-20250514" },
    { provider: "openai_apikey_responses", model: "gpt-5.4" }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
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

  def run_png_generation_for(provider:, model:)
    adapter = load_provider(provider:, model:)

    prompt = <<~PROMPT
      Use the python tool to read this CSV and create a PNG line chart.
      Requirements:
      - Plot monthly average temperature (Jan-Dec only; ignore Annual Mean)
      - Include x/y axes and month labels
      - Save the chart as a PNG file

      CSV:
      #{CSV_DATA}
    PROMPT

    tools = provider == "openai_apikey_responses" ? [ openai_code_interpreter_tool ] : [ anthropic_code_execution_tool ]

    streamed_args = +""
    response = adapter.stream(prompt, tools: tools) do |event|
      streamed_args += event.delta if event.type == :tool_delta
    end

    refute_equal "error", response.stop_reason, "#{provider}/#{model} failed: #{response.error_message}"

    content_types = response.content.map(&:type)

    if provider == "openai_apikey_responses"
      assert content_types.include?("code_interpreter_call") || content_types.include?("text"),
        "#{provider}/#{model} expected code_interpreter_call or text, got: #{content_types}"
    else
      assert content_types.include?("server_tool_use") || content_types.include?("tool_use") || content_types.include?("text"),
        "#{provider}/#{model} expected code execution activity or text, got: #{content_types}"
    end

    text = response.content.select { |b| b.type == "text" }.map(&:text).join("\n")
    unless text.empty?
      lower = text.downcase
      assert(lower.include?("png") || lower.include?("chart") || lower.include?("plot"),
        "#{provider}/#{model} expected text to mention png/chart/plot, got: #{text}")
    end

    refute_empty streamed_args unless streamed_args.empty?

    follow_up = "whats the name of the file and how many rows in the csv was there?"
    transcript = [
      { role: "user", content: prompt },
      response.to_h,
      { role: "user", content: follow_up }
    ]

    follow_up_response = adapter.stream(transcript, tools: tools)
    debugger
    refute_equal "error", follow_up_response.stop_reason,
      "#{provider}/#{model} follow-up failed: #{follow_up_response.error_message}"

    follow_up_text = follow_up_response.content.select { |b| b.type == "text" }.map(&:text).join("\n").downcase
    refute_empty follow_up_text, "#{provider}/#{model} expected follow-up text response"
    assert_includes follow_up_text, "png"
    assert_match(/\b(13|14)\b/, follow_up_text)
  end

  def self.define_live_png_test(provider:, model:)
    test "live_code_generation_png_#{provider}_#{model}" do
      skip_on_authentication_error do
        without_vcr do
          run_png_generation_for(provider:, model:)
        end
      end
    end
  end

  PROVIDER_MODEL_PAIRS.each do |pair|
    define_live_png_test(provider: pair[:provider], model: pair[:model])
  end
end
