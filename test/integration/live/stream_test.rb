# frozen_string_literal: true

require "test_helper"
require "vcr"
require "json"
require_relative "../../utils/calculator_tool_helper"
require_relative "../../utils/live_test_helper"

class StreamTest < Test
  include CalculatorToolHelper
  include LiveTestHelper

  def teardown
    LlmGateway.reset_configuration!
  end

  def assert_basic_text_generation_result(message, expected_text)
    assert_equal "assistant", message.role
    assert_operator message.usage[:input_tokens], :>, 0
    assert_operator message.usage[:output_tokens], :>, 0
    assert_nil message.error_message
    response_text = message.content
      .select { |block| block.type == "text" }
      .map(&:text)
      .join
    assert_includes response_text, expected_text
  end

  def basic_text_generation_test(adapter)
    first_prompt = "Reply with exactly: 'Hello test successful'"
    first_response = adapter.stream(first_prompt)

    assert_basic_text_generation_result(first_response, "Hello test successful")

    second_prompt = "Now say 'Goodbye test successful'"
    transcript = [
      { role: "user", content: first_prompt },
      first_response.to_h,
      { role: "user", content: second_prompt }
    ]
    second_response = adapter.stream(transcript)

    assert_basic_text_generation_result(second_response, "Goodbye test successful")
  end

  def basic_tool_call(adapter)
    prompt = "Calculate 15 + 27 using the math_operation tool"
    accumulated_tool_args = ""
    has_tool_start = false
    has_tool_delta = false
    has_tool_end = false
    response = adapter.stream(prompt, tools: [ math_operation_tool ]) do |event|
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
  end

  def basic_streaming_text_test(adapter)
    text_started = false
    text_chunks = ""
    text_completed = false

    response = adapter.stream("Count from 1 to 3") do |event|
      case event.type
      when :text_start
        text_started = true
        text_chunks += event.delta
      when :text_delta
        text_chunks += event.delta
      when :text_end
        text_completed = true
      end
    end

    assert_equal true, text_started, "text start event occurred"
    assert_operator text_chunks.length, :>, 0
    assert_equal true, text_completed, "text end event occurred"
    assert_equal "assistant", response.role
    assert response.content.any? { |block| block.type == "text" }
  end

  def multi_turn_tool_stream_test(adapter, reasoning: "high")
    transcript = [
      {
        role: "user",
        content: "Think about this briefly, then calculate 42 * 17 and 453 + 434 using the math_operation tool."
      }
    ]

    all_text_content = +""
    has_seen_thinking = false
    has_seen_tool_calls = false
    max_turns = 5

    max_turns.times do
      streamed_tool_args = Hash.new { |hash, key| hash[key] = +"" }

      stream_kwargs = {
        tools: [ math_operation_tool ],
        system: "You are a helpful assistant that can use tools to answer questions."
      }
      stream_kwargs[:reasoning] = reasoning if reasoning

      response = adapter.stream(
        transcript,
        **stream_kwargs
      ) do |event|
        case event.type
        when :reasoning_start, :reasoning_delta, :reasoning_end
          has_seen_thinking = true
        when :tool_start
          has_seen_tool_calls = true
          assert_equal "math_operation", event.name
          assert event.id
        when :tool_delta
          has_seen_tool_calls = true
          streamed_tool_args[event.content_index] += event.delta
        when :tool_end
          has_seen_tool_calls = true
        end
      end

      transcript << response.to_h

      results = []
      response.content.each_with_index do |block, index|
        case block.type
        when "text"
          all_text_content += block.text
        when "reasoning"
          has_seen_thinking = true
        when "tool_use"
          has_seen_tool_calls = true

          assert_equal "math_operation", block.name
          assert block.id
          refute_nil block.input
          refute_empty streamed_tool_args[index] unless streamed_tool_args[index].empty?

          result = evaluate_math_operation(block.input)

          results << {
            role: "developer",
            content: [
              {
                type: "tool_result",
                tool_use_id: block.id,
                content: result.to_s
              }
            ]
          }
        end
      end

      transcript.concat(results)

      refute_equal "error", response.stop_reason, "Error: #{response.error_message}"
      break if response.stop_reason == "stop"
    end

    assert_equal true, (has_seen_thinking || has_seen_tool_calls)

    if all_text_content.empty?
      assert_equal true, has_seen_tool_calls
    else
      assert_includes all_text_content, "714"
      assert_includes all_text_content, "887"
    end
  end

  def self.define_stream_tests_for(provider:, model:)
    test "live_basic_tool_call_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        basic_tool_call(adapter)
      end
    end


    test "live_text_streaming_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        basic_streaming_text_test(adapter)
      end
    end

    test "live_multi_turn_tool_streaming_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        multi_turn_tool_stream_test(adapter, reasoning: "high")
      end
    end
  end

  define_stream_tests_for(
    provider: "openai_apikey_completions",
    model: "gpt-5.1"
  )

  define_stream_tests_for(
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_tests_for(
    provider: "openai_apikey_responses",
    model: "gpt-5.4"
  )

  define_stream_tests_for(
    provider: "anthropic_oauth_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_tests_for(
    provider: "openai_oauth_codex",
    model: "gpt-5.4"
  )
end
