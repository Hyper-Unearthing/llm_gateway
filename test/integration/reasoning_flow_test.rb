# frozen_string_literal: true

require "test_helper"
require "vcr"

class ReasoningFlowTest < Test
  FIRST_QUESTION = "Think hard about how you would do rand(100)/8274. Do not actually execute rand(100) or reveal private chain-of-thought. Briefly explain the method and then give one concrete example using 42 as the random value.".freeze
  THIRD_QUESTION = "how are you".freeze
  SYSTEM = "Be concise. Mention 8274 and 42 in the final answer.".freeze

  def call_reasoning_turn(model, message, method = "chat", reasoning: "high")
    options = {
      system: SYSTEM,
      max_completion_tokens: 12 * 1024
    }
    options[:reasoning] = reasoning if reasoning

    LlmGateway::Client.send(method, model, message, **options)
  end

  test "claude maps thinking block across a return turn" do
    VCR.use_cassette(vcr_cassette_name) do
      transcript = [ { role: "user", content: FIRST_QUESTION } ]

      first_result = call_reasoning_turn("claude-sonnet-4-20250514", transcript)
      first_choice = first_result[:choices].first
      reasoning_block = first_choice[:content].find { |content| content[:type] == "reasoning" }

      refute_nil reasoning_block
      refute_nil reasoning_block[:reasoning]
      assert reasoning_block.key?(:signature)

      transcript << first_choice
      transcript << { role: "user", content: THIRD_QUESTION }

      second_result = call_reasoning_turn("claude-sonnet-4-20250514", transcript)
      second_choice = second_result[:choices].first

      assert_equal "assistant", second_choice[:role]
      refute_empty second_choice[:content]
    end
  end

  test "openai chat completions maps assistant response across a return turn" do
    VCR.use_cassette(vcr_cassette_name) do
      transcript = [ { role: "user", content: FIRST_QUESTION } ]

      first_result = call_reasoning_turn("o4-mini", transcript)
      first_choice = first_result[:choices].first

      assert_operator first_result.dig(:usage, :completion_tokens_details, :reasoning_tokens), :>, 0

      transcript << first_choice
      transcript << { role: "user", content: THIRD_QUESTION }

      second_result = call_reasoning_turn("o4-mini", transcript)
      second_choice = second_result[:choices].first

      assert_equal "assistant", second_choice[:role]
      refute_empty second_choice[:content]
    end
  end

  test "openai responses maps reasoning block across a return turn" do
    VCR.use_cassette(vcr_cassette_name) do
      transcript = [ { role: "user", content: [ { type: "text", text: FIRST_QUESTION } ] } ]
      first_result = call_reasoning_turn("o4-mini", transcript, "responses")
      reasoning_choice = first_result[:choices].find do |choice|
        choice[:content].is_a?(Array) && choice[:content].any? { |content| content[:type] == "reasoning" }
      end

      refute_nil reasoning_choice

      reasoning_block = reasoning_choice[:content].find { |content| content[:type] == "reasoning" }
      assert reasoning_block.key?(:reasoning)
      assert reasoning_block.key?(:signature)

      transcript.concat(first_result[:choices])
      transcript << { role: "user", content: [ { type: "text", text: THIRD_QUESTION } ] }

      second_result = call_reasoning_turn("o4-mini", transcript, "responses")
      assistant_choice = second_result[:choices].find { |choice| choice[:role] == "assistant" }

      refute_nil assistant_choice
      refute_empty assistant_choice[:content]
    end
  end
end
