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
        choices: [
          {
            content: [
              {
                type: "tool_use",
                id: "toolu_01CXTgvYbNLaweYSBS5cNs4v",
                name: "get_weather",
                input: { location: "Singapore" }
              }
            ],
            finish_reason: "tool_use",
            role: "assistant"
          }
        ],
        usage: {
          input_tokens: 404,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 53,
          service_tier: "standard"
        },
        model: "claude-sonnet-4-20250514",
        id: "msg_015UdpuDaJj36F1unnWafv9E"
      }
      assert_equal(expected, result)
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
        choices: [
          {
            content: [
              {
                text: "Get the weather in Singapore right now please matey",
                type: "text"
              }
            ]
          }
        ],
        usage: {
          queue_time: 0.05646005700000001,
          prompt_tokens: 237,
          prompt_time: 0.01188805,
          completion_tokens: 11,
          completion_time: 0.058864509,
          total_tokens: 248,
          total_time: 0.070752559
        },
        model: "llama-3.3-70b-versatile",
        id: "chatcmpl-a11a25f8-255b-44d3-b2bf-bebe3955f202"
      }
      assert_equal(expected, result)
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
        choices: [
          {
            content: [
              {
                id: "call_O8didtii93sfiSL8gZEuCZOu",
                type: "tool_use",
                name: "get_weather",
                input: { location: "Singapore" }
              }
            ]
          }
        ],
        usage: {
          prompt_tokens: 71,
          completion_tokens: 1559,
          total_tokens: 1630,
          prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
          completion_tokens_details: { reasoning_tokens: 1536, audio_tokens: 0, accepted_prediction_tokens: 0, rejected_prediction_tokens: 0 }
        },
        model: "o4-mini-2025-04-16",
        id: "chatcmpl-BmyTGK9K0teAfVyTKt2basqLFPZ6u"
      }
      assert_equal(expected, result)
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
        choices: [
          {
            content: [
              {
                text: "The weather in Singapore is usually hot and humid",
                type: "text"
              }
            ]
          }
        ],
        usage: {
          queue_time: 0.063591652,
          prompt_tokens: 55,
          prompt_time: 0.002805978,
          completion_tokens: 10,
          completion_time: 0.036363636,
          total_tokens: 65,
          total_time: 0.039169614
        },
        model: "llama-3.3-70b-versatile",
        id: "chatcmpl-d4f73973-6779-4008-bd46-4ee1e085ccab"
      }
      assert_equal(expected, result)
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
        choices: [
          {
            content: [
              {
                text: "Arr Singapore be sunny and humid with occasional afternoon showers",
                type: "text"
              }
            ]
          }
        ],
        usage: {
          prompt_tokens: 29,
          completion_tokens: 476,
          total_tokens: 505,
          prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
          completion_tokens_details: { reasoning_tokens: 448, audio_tokens: 0, accepted_prediction_tokens: 0, rejected_prediction_tokens: 0 }
        },
        model: "o4-mini-2025-04-16",
        id: "chatcmpl-BmySodNJA3sf37wwmWdM5HWxrTPbe"
      }
      assert_equal(expected, result)
    end
  end

  test "claude weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("claude-sonnet-4-20250514")
      expected = {
        choices: [
          {
            content: [
              {
                type: "text",
                text: "Ahoy matey Singapore be freezing cold at minus fifteen degrees"
              }
            ],
            finish_reason: "end_turn",
            role: "assistant"
          }
        ],
        usage: {
          input_tokens: 475,
          cache_creation_input_tokens: 0,
          cache_read_input_tokens: 0,
          output_tokens: 17,
          service_tier: "standard"
        },
        model: "claude-sonnet-4-20250514",
        id: "msg_01G6t3pgSqGyM6afjRTkVdPd"
      }
      assert_equal(expected, result)
    end
  end

  test "groq weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("llama-3.3-70b-versatile")
      expected = {
        content: [
          {
            text: "Get the weather in Singapore right now please matey",
            type: "text"
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
        choices: [
          {
            content: [
              {
                text: "Arr it is currently negative fifteen degrees Celsius in Singapore",
                type: "text"
              }
            ]
          }
        ],
        usage: {
          prompt_tokens: 103,
          completion_tokens: 604,
          total_tokens: 707,
          prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 },
          completion_tokens_details: { reasoning_tokens: 576, audio_tokens: 0, accepted_prediction_tokens: 0, rejected_prediction_tokens: 0 }
        },
        model: "o4-mini-2025-04-16",
        id: "chatcmpl-BmyT9vQHYy4lvkhRKdNN7P0LTDtHz"
      }
      assert_equal(expected, result)
    end
  end
end
