# frozen_string_literal: true

require "test_helper"
require "vcr"
require "base64"
require_relative "../../utils/live_test_helper"

class StreamImageTest < Test
  include LiveTestHelper

  def teardown
    LlmGateway.reset_configuration!
  end

  def basic_image_streaming_test(adapter)
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

    response = adapter.stream(prompt, system: "You are a helpful assistant.")

    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message

    text_content = response.content.find { |block| block.type == "text" }
    refute_nil text_content

    lower_content = text_content.text.downcase
    assert_includes lower_content, "red"
    assert_includes lower_content, "circle"
  end

  def self.define_stream_image_tests_for(provider:, model:)
    test "live_image_streaming_#{provider}_#{model}" do
      with_vcr_adapter(provider:, model:) do |adapter|
        basic_image_streaming_test(adapter)
      end
    end
  end

  define_stream_image_tests_for(
    provider: "openai_apikey_completions",
    model: "gpt-5.1"
  )

  define_stream_image_tests_for(
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_image_tests_for(
    provider: "openai_apikey_responses",
    model: "gpt-5.4"
  )

  define_stream_image_tests_for(
    provider: "anthropic_oauth_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_image_tests_for(
    provider: "openai_oauth_codex",
    model: "gpt-5.4"
  )
end
