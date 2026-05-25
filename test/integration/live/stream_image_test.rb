# frozen_string_literal: true

require "test_helper"
require "vcr"
require "base64"
require_relative "../../utils/live_test_helper"

class StreamImageTest < Test
  include LiveTestHelper

  PAIRS = [
    { name: "openai_apikey_completions", provider: "openai_completions", model: "gpt-5.1" },
    { name: "anthropic_apikey_messages", provider: "anthropic_messages", model: "claude-sonnet-4-20250514" },
    { name: "openai_apikey_responses", provider: "openai_responses", model: "gpt-5.4" },
    { name: "anthropic_oauth_messages", provider: "anthropic_messages", model: "claude-sonnet-4-20250514", oauth: true },
    { name: "openai_oauth_codex", provider: "openai_codex", model: "gpt-5.4" },
    { name: "groq_completions", provider: "groq_completions", model: "meta-llama/llama-4-scout-17b-16e-instruct", options: { max_completion_tokens: 8192, reasoning: "none" } }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def basic_image_streaming_test(adapter, options: {})
    image_path = File.expand_path("../../fixtures/red-circle.png", __dir__)
    image_data = Base64.strict_encode64(File.binread(image_path))

    prompt = [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "What do you see in this image? Please describe the shape (circle, rectangle, square, triangle, ...) and color (red, blue, green, ...). You MUST reply in English."
          },
          {
            type: "image",
            data: image_data,
            media_type: "image/png"
          }
        ]
      }
    ]

    message_end_event = nil
    response = adapter.stream(prompt, system: "You are a helpful assistant.", **options) do |event|
      message_end_event = event if event.type == :message_end
    end

    assert_stream_message_end_matches_response(message_end_event, response)
    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message

    text_content = response.content.find { |block| block.type == "text" }
    refute_nil text_content

    lower_content = text_content.text.downcase
    assert_includes lower_content, "red"
    assert_includes lower_content, "circle"

    response
  end

  def self.define_stream_image_tests_for(provider_name:, provider:, model:, oauth:, options: {})
    test "live_image_streaming_#{provider_name}_#{model}" do
      with_vcr_adapter(provider:, model:, oauth:,) do |adapter|
        response = basic_image_streaming_test(adapter, options: options)
        record_live_handoff_result(test_file: __FILE__, provider: provider_name, model:, result: response)
      end
    end
  end

  PAIRS.each do |pair|
    define_stream_image_tests_for(provider_name: pair[:name], provider: pair[:provider], model: pair[:model], oauth: pair[:oauth], options: pair.fetch(:options, {}))
  end
end
