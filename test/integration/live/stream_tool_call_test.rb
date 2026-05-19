# frozen_string_literal: true

require "test_helper"
require "vcr"
require "json"
require_relative "../../utils/calculator_tool_helper"
require_relative "../../utils/live_test_helper"

class StreamToolCallTest < Test
  include CalculatorToolHelper
  include LiveTestHelper

  PAIRS = [
    { provider: "openai_apikey_completions", model: "gpt-5.1" },
    { provider: "anthropic_apikey_messages", model: "claude-sonnet-4-20250514" },
    { provider: "openai_apikey_responses", model: "gpt-5.4" },
    { provider: "anthropic_oauth_messages", model: "claude-sonnet-4-20250514" },
    { provider: "openai_oauth_codex", model: "gpt-5.4" },
    { provider: "groq_completions", model: "openai/gpt-oss-120b" }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def basic_tool_call(adapter, options: {})
    prompt = "Calculate 15 + 27 using the math_operation tool"
    accumulated_tool_args = ""
    has_tool_start = false
    has_tool_delta = false
    has_tool_end = false
    response = adapter.stream(prompt, tools: [ math_operation_tool ], **options) do |event|
      if event.type == :tool_start
        has_tool_start = true
        assert_equal "math_operation", event.name
      end
      if event.type == :tool_delta
        has_tool_delta = true
        accumulated_tool_args += event.delta
      end
      if event.type == :tool_end
        has_tool_end = true
        parsed_args = JSON.parse(accumulated_tool_args)
        assert_equal(15, parsed_args["a"])
        assert_equal(27, parsed_args["b"])
        assert_equal("add", parsed_args["operation"])
      end
    end

    assert_equal true, has_tool_start, "tool start event occured"
    assert_equal true, has_tool_delta, "tool delta event occured"
    assert_equal true, has_tool_end, "tool end event occured"

    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message
    assert_includes [ "tool_use" ], response.stop_reason

    tool_call = response.content.find { |block| block.type == "tool_use" }
    refute_nil tool_call
    assert_equal "math_operation", tool_call.name
    assert tool_call.id
    refute_nil tool_call.input
    assert_equal 15, tool_call.input[:a]
    assert_equal 27, tool_call.input[:b]
    assert_includes %w[add subtract multiply divide], tool_call.input[:operation]

    response
  end

  def self.define_stream_tests_for(provider:, model:, options: {})
    test "live_basic_tool_call_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        response = basic_tool_call(adapter, options: options)
        record_live_handoff_result(test_file: __FILE__, provider:, model:, result: response)
      end
    end
  end

  PAIRS.each do |pair|
    define_stream_tests_for(provider: pair[:provider], model: pair[:model], options: pair.fetch(:options, {}))
  end
end
