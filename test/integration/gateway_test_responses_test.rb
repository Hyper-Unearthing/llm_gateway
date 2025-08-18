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
    result[:choices]&.each do |choice|
      transcript << choice
      next if choice[:content].is_a?(Hash)
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
        choices: [
          { id: "rs_68a323b3dc5c8193a672650245036c690a6c7f3a9118bc65", role: nil, content: [ { type: "reasoning", summary: [] } ] },
          { id: "fc_68a323c16cbc8193810c274efc03927b0a6c7f3a9118bc65", role: "assistant", content: [ { id: "call_O71QezmjypXwj1WFZgMeI9Id", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] }
        ],
        model: "o4-mini-2025-04-16",
        id: "resp_68a323b2a8f481939f56f4cc688f89b90a6c7f3a9118bc65",
        usage: { input_tokens: 67, input_tokens_details: { cached_tokens: 0 }, output_tokens: 1108, output_tokens_details: { reasoning_tokens: 1088 }, total_tokens: 1175 }
      }
      assert_equal(result, expected)
    end
  end


  SIMPLE_CHAT_RESPONSES = {
    id: "resp_68a2cb2d097c819fa544147ba1e7a1e909f86defd479c195",
    model: "o4-mini-2025-04-16",
    usage: { input_tokens: 29, input_tokens_details: { cached_tokens: 0 }, output_tokens: 530, output_tokens_details: { reasoning_tokens: 512 }, total_tokens: 559 },
    choices: [
      { id: "rs_68a2cb2df6ac819f8a0f5bd8cda1588e09f86defd479c195", role: nil, content: [ { type: "reasoning", summary: [] } ] },
      { id: "msg_68a2cb32dbe8819fb09e4f1ef5a1dc3e09f86defd479c195", role: "assistant", content: [ { type: "text", text: "Ahoy matey Singapore be hot and humid with tropical showers" } ] }
    ]
  }
  test "openai responses simple message without tools" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        system: "Talk like a pirate"
      )
      assert_equal(result, SIMPLE_CHAT_RESPONSES)
    end
  end

  test "openai responses simple message transcript" do
    VCR.use_cassette(vcr_cassette_name) do
      transcript = []
      transcript << SIMPLE_CHAT_RESPONSES[:choices]
      transcript << { role: "user", content: [ { type: "text", text: "what did you think about during your last response" } ] }
      result = LlmGateway::Client.responses(
        "o4-mini",
        transcript.flatten,
        system: "Talk like a pirate"
      )
      expected = {
        id: "resp_68a2f8cf2368819f8700d30951e4eb1609f86defd479c195",
        model: "o4-mini-2025-04-16",
        usage: { input_tokens: 41, input_tokens_details: { cached_tokens: 0 }, output_tokens: 309, output_tokens_details: { reasoning_tokens: 256 }, total_tokens: 350 },
        choices: [
          { id: "rs_68a2f8d055c4819f8ad6d0ce85d6f1c509f86defd479c195", role: nil, content: [ { type: "reasoning", summary: [] } ] },
          { id: "msg_68a2f8d2e968819faff8ce209562b33709f86defd479c195", role: "assistant", content: [ { type: "text", text: "Arrr, I don\u2019t have private musings like a human does. I simply set me sails for pirate-style speak and fetched a bit o\u2019 info on Singapore\u2019s sweltering, tropical clime to share with ye!" } ] }
        ]
      }
      assert_equal(result, expected)
    end
  end

  test "openai responses weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("gpt-5")
      expected = {
        choices: [ { id: "rs_68a34304495c8196ab43d8604def885c030d601903cb5ed5", role: nil, content: [ { type: "reasoning", summary: [] } ] }, { id: "msg_68a3430c5f188196908d239571186a78030d601903cb5ed5", role: "assistant", content: [  { type: "text", text: "Arr Singapore be a frosty minus fifteen degrees today matey" }  ] } ],
        model: "gpt-5-2025-08-07",
        id: "resp_68a34303e4908196a1f8503ed005f361030d601903cb5ed5",
        usage: { input_tokens: 359, input_tokens_details: { cached_tokens: 0 }, output_tokens: 722, output_tokens_details: { reasoning_tokens: 704 }, total_tokens: 1081 }
      }
      assert_equal(result, expected)
    end
  end
end
