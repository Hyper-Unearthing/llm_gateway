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
                id: "toolu_013LYTnUowbQcHw7i1JYj8ek",
                name: "get_weather",
                input: { location: "Singapore" }
              }
            ],
            finish_reason: "tool_use",
            role: "assistant"
          }
        ],
        usage: { input_tokens: 404, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 0 }, output_tokens: 53, service_tier: "standard" },
        model: "claude-sonnet-4-20250514",
        id: "msg_01AUZsdM9sPbZm6WjBy9CXNi"
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
        usage: { queue_time: 0.045523684, prompt_tokens: 237, prompt_time: 0.032411516, completion_tokens: 11, completion_time: 0.039058012, total_tokens: 248, total_time: 0.071469528 },
        model: "llama-3.3-70b-versatile",
        id: "chatcmpl-daedc002-441d-4d79-a91d-1e61de39dfee"
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
                id: "call_8DnGFFRKGF8xYpaT7AZqFKHc",
                type: "tool_use",
                name: "get_weather",
                input: { location: "Singapore" }
              }
            ]
          }
        ],
        usage: { prompt_tokens: 71, completion_tokens: 215, total_tokens: 286, prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 }, completion_tokens_details: { reasoning_tokens: 192, audio_tokens: 0, accepted_prediction_tokens: 0, rejected_prediction_tokens: 0 } },
        id: "chatcmpl-C5Zba9y9OG70FEV8Ber4LIrtxlXdd",
        model: "o4-mini-2025-04-16"
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
                text: "The weather in Singapore is usually hot and very humid",
                type: "text"
              }
            ]
          }
        ],
        usage: { queue_time: 0.044468705, prompt_tokens: 55, prompt_time: 0.011753645, completion_tokens: 11, completion_time: 0.03198708, total_tokens: 66, total_time: 0.043740725 },
        id: "chatcmpl-5de6e422-9002-437c-b118-5a378bb9e364",
        model: "llama-3.3-70b-versatile"
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
                text: "arr matey it be sunny and humid in singapore today",
                type: "text"
              }
            ]
          }
        ],
        usage: { prompt_tokens: 29, completion_tokens: 413, total_tokens: 442, prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 }, completion_tokens_details: { reasoning_tokens: 384, audio_tokens: 0, accepted_prediction_tokens: 0, rejected_prediction_tokens: 0 } },
        id: "chatcmpl-C5Zbqa3BeMwr7OUtARXvoUfRrrngZ",
        model: "o4-mini-2025-04-16"
      }
      assert_equal(expected, result)
    end
  end

  test "claude weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("claude-sonnet-4-20250514")
      expected = {
        choices: [ { content: [ { type: "text", text: "Arrr matey Singapore be mighty cold at negative fifteen degrees" } ], finish_reason: "end_turn", role: "assistant" } ],
        usage: { input_tokens: 475, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, cache_creation: { ephemeral_5m_input_tokens: 0, ephemeral_1h_input_tokens: 0 }, output_tokens: 16, service_tier: "standard" },
        model: "claude-sonnet-4-20250514",
        id: "msg_01SJa9Udt1peeTMZxmZoV9t5"
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
                text: "Arrr it be minus fifteen degrees in Singapore today matey!",
                type: "text"
              }
            ]
          }
        ],
        usage: { prompt_tokens: 103, completion_tokens: 25, total_tokens: 128, prompt_tokens_details: { cached_tokens: 0, audio_tokens: 0 }, completion_tokens_details: { reasoning_tokens: 0, audio_tokens: 0, accepted_prediction_tokens: 0, rejected_prediction_tokens: 0 } },
        id: "chatcmpl-C5Zw2oSyhLzRaNHUdtvdbMtLqooIH",
        model: "o4-mini-2025-04-16"
      }
      assert_equal(expected, result)
    end
  end
end
