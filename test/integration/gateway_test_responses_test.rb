# frozen_string_literal: true

require "test_helper"
require "vcr"

class GatewayResponsesTest < Test
  def call_gateway_with_tool_response(model_id)
    transcript = []
    message = "What's the weather in Singapore? reply in 10 words and no special characters"

    # Track user message
    transcript << { role: "user", content: message }

    # Call gateway
    result = LlmGateway::Client.responses(
      model_id,
      message,
      tools: [ weather_tool ],
      system: "Talk like a pirate"
    )
    transcript = transcript + result.transcript

    result[:choices]&.each do |choice|
      choice[:content].each do |content|
        next unless content[:type] == "tool_use" && content[:name] == "get_weather"
        handle_weather_tool(content[:input]).tap do |weather_response|
          transcript << {
            role: "developer",
            content: [ { content: weather_response, type: "tool_result", tool_use_id: content[:id] } ]
          }
          result = LlmGateway::Client.responses(
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

  test "openai responses weather with pirate system" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        tools: [ weather_tool ],
        system: "Talk like a pirate"
      )
      expected = {
        choices: [ { content: [ { id: "call_JrFWuUvGdMnyKePJh2FeU5dv", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] } ],
        model: "o4-mini-2025-04-16",
        id: "resp_68962278badc8192a70cb79cf93cef170612055fe18b5a81",
        usage: { input_tokens: 67, input_tokens_details: { cached_tokens: 0 }, output_tokens: 660, output_tokens_details: { reasoning_tokens: 640 }, total_tokens: 727 }
      }
      assert_equal(result, expected)
    end
  end

  test "openai responses simple message without tools" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        system: "Talk like a pirate"
      )
      expected = {
        choices: [ { content: [ { type: "text", text: "Arrr cloudy skies be above Singapore with warm humid air" } ] } ],
        model: "o4-mini-2025-04-16",
        id: "resp_68961c57892481a0aba0a708af535a570370539d256d9e9c",
        usage: { input_tokens: 29, input_tokens_details: { cached_tokens: 0 }, output_tokens: 1361, output_tokens_details: { reasoning_tokens: 1344 }, total_tokens: 1390 }
      }
      assert_equal(result, expected)
    end
  end

  test "openai responses weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("gpt-5")
      expected = {
        choices: [ { content: [ { type: "text", text: "Singapore weather be minus fifteen celsius me spyglass be faulty" } ] } ],
        model: "gpt-5-2025-08-07",
        id: "resp_68963b371d7881a1a56f495625c4a8ba01d958b851dfcf8e",
        usage: { input_tokens: 253, input_tokens_details: { cached_tokens: 0 }, output_tokens: 1298, output_tokens_details: { reasoning_tokens: 1280 }, total_tokens: 1551 }
      }
      assert_equal(result, expected)
    end
  end


  test "claude responses weather with pirate system" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses(
        "claude-sonnet-4-20250514",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        tools: [ weather_tool ],
        system: "Talk like a pirate"
      )
      expected = {
        id: "msg_01TKLooJ8MR9v4q6n4EAkeLE",
        model: "claude-sonnet-4-20250514",
        usage: { input_tokens: 404, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 53, service_tier: "standard" },
        choices: [ { content: [ { type: "tool_use", id: "toolu_01WfPbcMYFCgdJxTubMSjTLz", name: "get_weather", input: { location: "Singapore" } } ], finish_reason: "tool_use", role: "assistant" } ]
      }
      assert_equal(result, expected)
    end
  end

  test "claude responses weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("claude-sonnet-4-20250514")
      expected = {
        id: "msg_01Ur8jBS1oxfu8u9gXKiBuY7",
        model: "claude-sonnet-4-20250514",
        usage: { input_tokens: 475, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 16, service_tier: "standard" },
        choices: [ { content: [ { type: "text", text: "Arrr matey Singapore be mighty cold at negative fifteen degrees" } ], finish_reason: "end_turn", role: "assistant" } ]
      }
      assert_equal(result, expected)
    end
  end

  # test "groq weather with pirate system with tool usage" do
  #   VCR.use_cassette(vcr_cassette_name) do
  #     result = call_gateway_with_tool_response("llama-3.3-70b-versatile")
  #     expected = {
  #       content: [
  #         {
  #           text: "Get the weather in Singapore right now please matey",
  #           type: "text"
  #         }
  #       ]
  #     }
  #     assert_equal(expected, result)
  #   end
  # end
  #
  #  test "groq simple message without tools" do
  #   VCR.use_cassette(vcr_cassette_name) do
  #     result = LlmGateway::Client.chat(
  #       "llama-3.3-70b-versatile",
  #       "What's the weather in Singapore? reply in 10 words and no special characters",
  #       system: "Talk like a pirate"
  #     )
  #     expected = {
  #       choices: [
  #         {
  #           content: [
  #             {
  #               text: "The weather in Singapore is usually hot and humid",
  #               type: "text"
  #             }
  #           ]
  #         }
  #       ],
  #       usage: {
  #         queue_time: 0.063591652,
  #         prompt_tokens: 55,
  #         prompt_time: 0.002805978,
  #         completion_tokens: 10,
  #         completion_time: 0.036363636,
  #         total_tokens: 65,
  #         total_time: 0.039169614
  #       },
  #       model: "llama-3.3-70b-versatile",
  #       id: "chatcmpl-d4f73973-6779-4008-bd46-4ee1e085ccab"
  #     }
  #     assert_equal(expected, result)
  #   end
  # end
end
