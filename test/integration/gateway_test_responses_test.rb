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
        id: ->(value, path) { assert_match(/\Aresp_/, value, path) },
        model: "o4-mini-2025-04-16",
        usage: {
          input_tokens: 67,
          input_tokens_details: { cached_tokens: 0 },
          output_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          output_tokens_details: { reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path } },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path }
        },
        choices: [
          {
            id: ->(value, path) { assert_match(/\Ars_/, value, path) },
            role: nil,
            content: [ { type: "reasoning", summary: [] } ]
          },
          {
            id: ->(value, path) { assert_match(/\Afc_/, value, path) },
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


  test "openai responses simple message without tools" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses(
        "o4-mini",
        "What's the weather in Singapore? reply in 10 words and no special characters",
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Aresp_/, value, path) },
        model: "o4-mini-2025-04-16",
        usage: {
          input_tokens: 29,
          input_tokens_details: { cached_tokens: 0 },
          output_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          output_tokens_details: { reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path } },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path }
        },
        choices: [
          {
            id: ->(value, path) { assert_match(/\Ars_/, value, path) },
            role: nil,
            content: [ { type: "reasoning", summary: [] } ]
          },
          {
            id: ->(value, path) { assert_match(/\Amsg_/, value, path) },
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

  test "openai responses simple message transcript" do
    VCR.use_cassette(vcr_cassette_name) do
      # Use the IDs baked into the VCR cassette for the transcript input
      prior_choices = [
        { id: "rs_68a2cb2df6ac819f8a0f5bd8cda1588e09f86defd479c195", role: nil, content: [ { type: "reasoning", summary: [] } ] },
        { id: "msg_68a2cb32dbe8819fb09e4f1ef5a1dc3e09f86defd479c195", role: "assistant", content: [ { type: "text", text: "Ahoy matey Singapore be hot and humid with tropical showers" } ] }
      ]
      transcript = []
      transcript << prior_choices
      transcript << { role: "user", content: [ { type: "text", text: "what did you think about during your last response" } ] }
      result = LlmGateway::Client.responses(
        "o4-mini",
        transcript.flatten,
        system: "Talk like a pirate"
      )
      expected = {
        id: ->(value, path) { assert_match(/\Aresp_/, value, path) },
        model: "o4-mini-2025-04-16",
        usage: {
          input_tokens: ->(value, path) { assert_kind_of Integer, value, path },
          input_tokens_details: { cached_tokens: 0 },
          output_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          output_tokens_details: { reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path } },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path }
        },
        choices: [
          {
            id: ->(value, path) { assert_match(/\Ars_/, value, path) },
            role: nil,
            content: [ { type: "reasoning", summary: [] } ]
          },
          {
            id: ->(value, path) { assert_match(/\Amsg_/, value, path) },
            role: "assistant",
            content: [
              {
                type: "text",
                text: ->(value, path) { assert_match(/pirate|singapore|weather/i, value, path) }
              }
            ]
          }
        ]
      }
      assert_llm_response(expected, result)
    end
  end

  test "openai responses weather with pirate system with tool usage" do
    VCR.use_cassette(vcr_cassette_name) do
      result = call_gateway_with_tool_response("gpt-5")
      expected = {
        id: ->(value, path) { assert_match(/\Aresp_/, value, path) },
        model: ->(value, path) { assert_kind_of String, value, path },
        usage: {
          input_tokens: ->(value, path) { assert_kind_of Integer, value, path },
          input_tokens_details: { cached_tokens: 0 },
          output_tokens: ->(value, path) { assert_operator value, :>, 0, path },
          output_tokens_details: { reasoning_tokens: ->(value, path) { assert_kind_of Integer, value, path } },
          total_tokens: ->(value, path) { assert_operator value, :>, 0, path }
        },
        choices: [
          {
            id: ->(value, path) { assert_match(/\Ars_/, value, path) },
            role: nil,
            content: [ { type: "reasoning", summary: [] } ]
          },
          {
            id: ->(value, path) { assert_match(/\Amsg_/, value, path) },
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
end
