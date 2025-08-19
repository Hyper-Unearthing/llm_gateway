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
        id: "resp_68a43e3dd18481908d49a17ff130705b06e99912c9374f3d",
        model: "o4-mini-2025-04-16",
        usage: { input_tokens: 67, input_tokens_details: { cached_tokens: 0 }, output_tokens: 532, output_tokens_details: { reasoning_tokens: 512 }, total_tokens: 599 },
        choices: [
          { id: "rs_68a43e3e8da08190afd59c68125d001306e99912c9374f3d", role: nil, content: [ { type: "reasoning", summary: [] } ] },
          { id: "fc_68a43e460a5081909f36553c34cc410606e99912c9374f3d", role: "assistant", content: [ { id: "call_0vSMgJt1QT6hyiTQo6IWO3mR", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] }
        ]
      }
      assert_equal(expected, result)
    end
  end

  SIMPLE_CHAT_RESPONSES = {
    id: "resp_68a43ca8e368819f95c7966de455e0fd0a22cd2a1e773f3b",
    model: "o4-mini-2025-04-16",
    usage: { input_tokens: 29, input_tokens_details: { cached_tokens: 0 }, output_tokens: 593, output_tokens_details: { reasoning_tokens: 576 }, total_tokens: 622 },
    choices: [
      { id: "rs_68a43ca96c98819f9cc048c486aec0350a22cd2a1e773f3b", role: nil, content: [ { type: "reasoning", summary: [] } ] },
      { id: "msg_68a43cb13860819f81a096bd68f48e140a22cd2a1e773f3b", role: "assistant", content: [ { type: "text", text: "Arrr the weather in Singapore be hot humid with rain" } ] }
    ]
  }
  test "openai responses simple message without tools" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        system: "Talk like a pirate"
      )
      assert_equal(SIMPLE_CHAT_RESPONSES, result)
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
        id: "resp_68a43e597ef4819f924c03d76c0f9b2b0a22cd2a1e773f3b", \
        model: "o4-mini-2025-04-16",
        usage: { input_tokens: 40, input_tokens_details: { cached_tokens: 0 }, output_tokens: 387, output_tokens_details: { reasoning_tokens: 320 }, total_tokens: 427 },
        choices: [
          { id: "rs_68a43e5a3b04819f9b0591945b030dbc0a22cd2a1e773f3b", role: nil, content: [ { type: "reasoning", summary: [] } ] },
          { id: "msg_68a43e5de7e0819fa3720984049ca9460a22cd2a1e773f3b", role: "assistant", content: [ { type: "text", text: "Arrr, matey! I can\u2019t be revealin\u2019 me private thinkin\u2019, but I was chartin\u2019 a swift, pirate-style weather report for Singapore\u2014markin\u2019 its heat, humidity, and rain\u2014and craftin\u2019 me words to sound like a true buccaneer." } ] }
        ]
      }
      assert_equal(expected, result)
    end
  end

  # { , choices: [ , { id: "msg_68a43e5de7e0819fa3720984049ca9460a22cd2a1e773f3b", role: "assistant", content: [ { type: "text", text: "Arrr, matey! I can’t be revealin’ me private thinkin’, but I was chartin’ a swift, pirate-style weather report for Singapore—markin’ its heat, humidity, and rain—and craftin’ me words to sound like a true buccaneer." } ] } ] }
  test "openai responses weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("gpt-5")
      expected = {
        id: "resp_68a43c98fcf0819cae219eea47bf9eaf025ae319a497c89f",
        model: "gpt-5-2025-08-07",
        usage: { input_tokens: 472, input_tokens_details: { cached_tokens: 0 }, output_tokens: 1171, output_tokens_details: { reasoning_tokens: 1152 }, total_tokens: 1643 },
        choices: [
          { id: "rs_68a43c99b94c819c96f9a43243c23f03025ae319a497c89f", role: nil, content: [ { type: "reasoning", summary: [] } ] },
          { id: "msg_68a43ca8045c819cb2b052b976146224025ae319a497c89f", role: "assistant", content: [ { type: "text", text: "Arr matey me spyglass be fogged cannot report Singapore weather" } ] }
        ]
      }
      assert_equal(expected, result)
    end
  end
end
