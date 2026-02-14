# frozen_string_literal: true

require "test_helper"
require "vcr"

class GatewayTest < Test
  def call_gateway_with_tool_response(model_id)
    transcript = []
    message = "What's the weather in Singapore? reply in 10 words and no special characters"

    # Track user message
    transcript << { role: "user", content: message }

    # Call gateway
    result = LlmGateway::Client.chat(
      model_id,
      message,
      tools: [ weather_tool ],
      system: "Talk like a pirate"
    )
    result[:choices]&.each do |choice|
      transcript << choice
      choice[:content].each do |content|
        next unless content[:type] == "tool_use" && content[:name] == "get_weather"

        handle_weather_tool(content[:input]).tap do |weather_response|
          transcript << {
            role: "developer",
            content: [ { content: weather_response, type: "tool_result", tool_use_id: content[:id] } ]
          }
          result = LlmGateway::Client.chat(
            model_id,
            transcript,
            tools: [ weather_tool ],
            system: "Talk like a pirate"
          )
          transcript << result
        end
      end
    end
    transcript.last
  end

  def handle_weather_tool(params)
    location = params[:location]
    # Simulate a weather API response
    raise "Location not supported" unless location == "Singapore"

    "-15 celcius"
  end

  def weather_tool
    {
      name: "get_weather",
      description: "Get current weather for a location",
      input_schema: {
        type: "object",
        properties: {
          location: { type: "string", description: "City name" }
        },
        required: [ "location" ]
      }
    }
  end

  test "claude weather with pirate system" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "claude-sonnet-4-20250514",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        tools: [ weather_tool ],
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Amsg_/, value, path) },
        model: "claude-sonnet-4-20250514",
        usage: {
          input_tokens: 404,
          output_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 0 },
          service_tier: "standard",
          inference_geo: "not_available"
        },
        choices: [
          {
            content: [
              {
                type: "tool_use",
                id: ->(value, path) { assert_match(/\Atoolu_/, value, path) },
                name: "get_weather",
                input: { location: "Singapore" }
              }
            ],
            finish_reason: "tool_use",
            role: "assistant"
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "groq weather with pirate system" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "llama-3.3-70b-versatile",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        tools: [ weather_tool ],
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Achatcmpl-/, value, path) },
        model: "llama-3.3-70b-versatile",
        usage: {
          prompt_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          completion_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          queue_time: ->(value, path) { assert_kind_of Numeric, value, path },
          prompt_time: ->(value, path) { assert_kind_of Numeric, value, path },
          completion_time: ->(value, path) { assert_kind_of Numeric, value, path },
          total_time: ->(value, path) { assert_kind_of Numeric, value, path }
        },
        choices: [
          {
            role: "assistant",
            content: [
              {
                type: "text",
                text: ->(value, path) { assert_match(/singapore|weather/i, value, path) }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "openai weather with pirate system" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        tools: [ weather_tool ],
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Achatcmpl-/, value, path) },
        model: "o4-mini-2025-04-16",
        usage: {
          prompt_tokens: 71,
          completion_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
          completion_tokens_details: {
            reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path },
            audio_tokens: 0,
            accepted_prediction_tokens: 0,
            rejected_prediction_tokens: 0
          }
        },
        choices: [
          {
            role: "assistant",
            content: [
              {
                id: ->(value, path) { assert_match(/\Acall_/, value, path) },
                type: "tool_use",
                name: "get_weather",
                input: { location: "Singapore" }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "groq simple message without tools" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "llama-3.3-70b-versatile",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Achatcmpl-/, value, path) },
        model: "llama-3.3-70b-versatile",
        usage: {
          prompt_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          completion_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          queue_time: ->(value, path) { assert_kind_of Numeric, value, path },
          prompt_time: ->(value, path) { assert_kind_of Numeric, value, path },
          completion_time: ->(value, path) { assert_kind_of Numeric, value, path },
          total_time: ->(value, path) { assert_kind_of Numeric, value, path }
        },
        choices: [
          {
            role: "assistant",
            content: [
              {
                type: "text",
                text: ->(value, path) { assert_match(/singapore|weather|hot|humid/i, value, path) }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "openai simple message without tools" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Achatcmpl-/, value, path) },
        model: "o4-mini-2025-04-16",
        usage: {
          prompt_tokens: 29,
          completion_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
          completion_tokens_details: {
            reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path },
            audio_tokens: 0,
            accepted_prediction_tokens: 0,
            rejected_prediction_tokens: 0
          }
        },
        choices: [
          {
            role: "assistant",
            content: [
              {
                type: "text",
                text: ->(value, path) { assert_match(/singapore/i, value, path) }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "claude weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("claude-sonnet-4-20250514")
      expected = {
        id: ->(value, path) { assert_match(/\Amsg_/, value, path) },
        model: "claude-sonnet-4-20250514",
        usage: {
          input_tokens: 475,
          output_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 0 },
          service_tier: "standard",
          inference_geo: "not_available"
        },
        choices: [
          {
            role: "assistant",
            finish_reason: "end_turn",
            content: [
              {
                type: "text",
                text: ->(value, path) {
                  assert_match(/singapore/i, value, path)
                  assert_match(/fifteen/i, value, path)
                  assert_match(/ahoy|arr|matey/i, value, path)
                }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "groq weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("llama-3.3-70b-versatile")
      expected = {
        role: "assistant",
        content: [
          {
            type: "text",
            text: "Get the weather in Singapore right now please matey"
          }
        ]
      }
      assert_equal(expected, result)
    end
  end

  test "openai weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("o4-mini")
      expected = {
        id: ->(value, path) { assert_match(/\Achatcmpl-/, value, path) },
        model: "o4-mini-2025-04-16",
        usage: {
          prompt_tokens: ->(value, path) { assert_kind_of Integer, value, path },
          completion_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
          completion_tokens_details: {
            reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path },
            audio_tokens: 0,
            accepted_prediction_tokens: 0,
            rejected_prediction_tokens: 0
          }
        },
        choices: [
          {
            role: "assistant",
            content: [
              {
                type: "text",
                text: ->(value, path) {
                  assert_match(/singapore/i, value, path)
                  assert_match(/fifteen/i, value, path)
                }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end
end
