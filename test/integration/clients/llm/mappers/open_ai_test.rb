# frozen_string_literal: true

require "test_helper"

class OpenAIMapperTest < Test
  test "open ai input mapper tool usage" do
    input = {
      messages: [ { role: "user", content: "What's the weather in Singapore? reply in 10 words and no special characters" },
             { content: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] },
             { role: "developer", content: [ { content: "-15 celcius", type: "tool_result", tool_use_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ" } ] } ],
      response_format: { type: "text" },
      tools: [ { name: "get_weather", description: "Get current weather for a location", input_schema: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } } ],
      system: [ { role: "system", content: "Talk like a pirate" } ]
    }


    expectation ={
      system: [ { role: "developer", content: "Talk like a pirate" } ],
      response_format: { type: "text" },
      messages: [ { role: "user", content: [ { type: "text", text: "What's the weather in Singapore? reply in 10 words and no special characters" } ] },
       {
         role: "assistant",
         content: nil,
         tool_calls: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "function", function: { name: "get_weather", arguments: "{\"location\":\"Singapore\"}" } } ]
       },
       {
         role: "tool",
         tool_call_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ",
         content: "-15 celcius"
       } ],
      tools: [ {
        type: "function",
        function: { name: "get_weather", description: "Get current weather for a location", parameters: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } }
      } ]
    }
    result = LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper.map(input)
    assert_equal expectation, result
  end

  test "open ai input mapper tool usage, with role assistant " do
    input = {
      messages: [ { role: "user", content: "What's the weather in Singapore? reply in 10 words and no special characters" },
             { role: "assistant", content: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] },
             { role: "developer", content: [ { content: "-15 celcius", type: "tool_result", tool_use_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ" } ] } ],
      response_format: { type: "text" },
      tools: [ { name: "get_weather", description: "Get current weather for a location", input_schema: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } } ],
      system: [ { role: "system", content: "Talk like a pirate" } ]
    }


    expectation ={
      system: [ { role: "developer", content: "Talk like a pirate" } ],
      response_format: { type: "text" },
      messages: [ { role: "user", content: [ { type: "text", text: "What's the weather in Singapore? reply in 10 words and no special characters" } ] },
       {
         role: "assistant",
         content: nil,
         tool_calls: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "function", function: { name: "get_weather", arguments: "{\"location\":\"Singapore\"}" } } ]
       },
       {
         role: "tool",
         tool_call_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ",
         content: "-15 celcius"
       } ],
      tools: [ {
        type: "function",
        function: { name: "get_weather", description: "Get current weather for a location", parameters: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } }
      } ]
    }
    result = LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper.map(input)

    assert_equal expectation, result
  end
end
