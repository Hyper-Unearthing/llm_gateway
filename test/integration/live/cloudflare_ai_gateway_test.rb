# frozen_string_literal: true

require "test_helper"
require_relative "../../utils/live_test_helper"
require_relative "../../utils/calculator_tool_helper"

class CloudflareAIGatewayLiveTest < Test
  include LiveTestHelper
  include CalculatorToolHelper

  PAIRS = [
    { model: "openai/gpt-5.4-nano", reports_usage: true, options: { max_completion_tokens: 256, reasoning_effort: "none", stream_options: { include_usage: true } } },
    { model: "anthropic/claude-haiku-5-5", reports_usage: false, options: { max_completion_tokens: 256, stream_options: { include_usage: true } } }
  ].freeze

  PAIRS.each do |pair|
    model = pair.fetch(:model)
    options = pair.fetch(:options)

    test "cloudflare_text_stream_#{model}" do
      with_vcr_adapter(provider: "cloudflare-ai-gateway", model: model) do |adapter|
        message_end = nil
        response = adapter.stream("Reply with exactly the word blue.", **options) do |event|
          message_end = event if event.type == :message_end
        end
        assert_stream_message_end_matches_response(message_end, response)
        assert_equal "cloudflare-ai-gateway", response.provider
        assert_equal "completions", response.api
        assert_equal "stop", response.stop_reason, response.error_message
        assert_includes text_for(response), "blue"
        if pair.fetch(:reports_usage)
          assert_operator response.usage[:input], :>, 0
          assert_operator response.usage[:output], :>, 0
          assert_usage_costs(response)
        else
          # The compatibility endpoint omits Anthropic usage frames even when
          # include_usage is requested. Missing counts must not be fabricated.
          assert_empty response.usage[:raw]
          assert_equal 0, response.usage[:input]
          assert_equal 0, response.usage[:output]
          assert_nil response.usage[:cost]
        end
      end
    end

    test "cloudflare_tool_round_trip_#{model}" do
      with_vcr_adapter(provider: "cloudflare-ai-gateway", model: model) do |adapter|
        transcript = [ { role: "user", content: "Calculate 15 + 27 using exactly one math_operation tool call. Wait for the tool result." } ]
        response = adapter.stream(transcript, tools: [ math_operation_tool ], **options)
        assert_equal "tool_use", response.stop_reason, response.error_message
        calls = response.content.select { |block| block.type == "tool_use" }
        assert_equal 1, calls.length
        call = calls.first
        assert_equal "math_operation", call.name
        assert_equal 42, evaluate_math_operation(call.input)
        transcript << response.to_h
        transcript << { role: "user", content: [ { type: "tool_result", tool_use_id: call.id, content: "42" } ] }
        answer = adapter.stream(transcript, tools: [ math_operation_tool ], **options)
        assert_equal "stop", answer.stop_reason, answer.error_message
        assert_includes text_for(answer), "42"
      end
    end

    test "cloudflare_receives_mixed_provider_transcript_#{model}" do
      with_vcr_adapter(provider: "cloudflare-ai-gateway", model: model) do |adapter|
        paths = Dir.glob(File.expand_path("../../fixtures/handoff/stream_text_test/*.json", __dir__)).sort
        refute_empty paths
        transcript = paths.flat_map { |path| deep_symbolize(JSON.parse(File.read(path))) }
        transcript << { role: "user", content: <<~PROMPT }
          The preceding messages are archived exchanges from different assistants.
          Read their replies rather than carrying out the earlier user requests again.
          What ordered number sequence did the assistants return? Reply only with that sequence, using digits separated by commas.
        PROMPT
        response = adapter.stream(transcript, **options)
        assert_equal "stop", response.stop_reason, response.error_message
        assert_match(/\b1\s*,\s*2\s*,\s*3\b/, text_for(response))
      end
    end
  end

  private

  def text_for(response)
    response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
  end
end
