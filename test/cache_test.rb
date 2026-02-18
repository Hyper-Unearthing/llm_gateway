
# frozen_string_literal: true

require "test_helper"

class CacheTest < Test
  class TestClient
    CHAT_RESPONSE = {
      id: "msg_123",
      model: "claude-3",
      usage: { input_tokens: 10, output_tokens: 5 },
      content: [ { type: "text", text: "hello" } ],
      stop_reason: "end_turn"
    }.freeze

    def chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096)
      CHAT_RESPONSE
    end
  end

  test "when cache marker is passed to last message" do
    message = [
      {
        role: "user",
        content: [
          { type: "text", text: "return the content of the document exactly", cache_control: { 'type': "ephemeral" } }
        ]
      }
    ]

    client = TestClient.new
    client.expects(:chat).once.with(
      [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly", cache_control: { 'type': "ephemeral" } } ] } ],
      response_format: anything,
      tools: anything,
      system: anything
    ).returns(TestClient::CHAT_RESPONSE)

    adapter = LlmGateway::Adapters::Claude::MessagesAdapter.new client

    adapter.chat(message)
  end


  test "when cache marker passed with system message" do
    client = TestClient.new
    client.expects(:chat).once.with(
      anything,
      response_format: anything,
      tools: anything,
      system: [ { type: "text", text: "do it proper", cache_control: { 'type': "ephemeral" } } ]
    ).returns(TestClient::CHAT_RESPONSE)

    adapter = LlmGateway::Adapters::Claude::MessagesAdapter.new client

    adapter.chat("hello", system: [ { role: "system", content: "do it proper", cache_control: { 'type': "ephemeral" } } ])
  end

  test "when cache marker passed with tool" do
    client = TestClient.new
    adapter = LlmGateway::Adapters::Claude::MessagesAdapter.new client

    tools = [ { name: "get_weather", description: "Get current weather for a location", cache_control: { 'type': "ephemeral" }, input_schema: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } } ]

    client.expects(:chat).once.with(
      anything,
      response_format: anything,
      tools: tools,
      system: anything
    ).returns(TestClient::CHAT_RESPONSE)

    adapter.chat("hello", tools: tools)
  end

  test "tool_result should propergate cache control as well" do
    [ { role: "user", content: [ { type: "text", text: "what pull requests were opened this month" } ] }, {
      role: "assistant",
      content: [ {
        type: "text",
        text: "I'll help you find the pull requests that were opened this month. Let me fetch that information for you."
      }, {
        type: "tool_use",
        id: "toolu_01SEgaEYS5ccNw6s9HT7TKMK",
        name: "fetch_pull_requests",
        input: {
          parameters: "abc"
        }
      } ]
    }, {
      role: "developer",
      content: [ {
        type: "tool_result",
        tool_use_id: "toolu_01SEgaEYS5ccNw6s9HT7TKMK",
        content: "hello world",
        cache_control: { 'type': "ephemeral" }
      } ]
    } ]
  end
end
