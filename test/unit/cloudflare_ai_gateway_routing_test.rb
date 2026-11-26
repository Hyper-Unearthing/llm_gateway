# frozen_string_literal: true

require "test_helper"
require "stringio"

class CloudflareAIGatewayRoutingTest < Test
  ACCOUNT_ID = "a" * 32
  ROOT = "https://api.cloudflare.com/client/v4/accounts/#{ACCOUNT_ID}/ai/v1"
  TOOL = { name: "calculate", description: "Calculate a result", input_schema: { type: "object", properties: {} } }.freeze
  PAIRS = [
    [ "anthropic/claude-haiku-5.5", "claude-haiku-5-5", "https://gateway.ai.cloudflare.com/v1/#{ACCOUNT_ID}/test-gateway/anthropic/v1/messages", true ],
    [ "minimax/m3.1-flash", "minimax/m3.1-flash", "#{ROOT}/messages", true ],
    [ "openai/gpt-5.4-nano", "openai/gpt-5.4-nano", "#{ROOT}/chat/completions", false ],
    [ "deepseek/deepseek-v4-pro", "deepseek/deepseek-v4-pro", "#{ROOT}/chat/completions", false ]
  ].freeze

  def setup
    super
    WebMock.reset!
  end

  def teardown
    WebMock.reset!
    super
  end

  PAIRS.each do |id, wire_model, endpoint, messages_api|
    test "routes #{id} without exposing protocol selection to callers" do
      model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: id)
      request = stub_request(:post, endpoint).with do |req|
        body = JSON.parse(req.body)
        assert_equal wire_model, body["model"]
        assert_equal true, body["stream"]
        assert_equal "user", body["messages"].last["role"]
        if messages_api
          assert_equal "calculate", body.dig("tools", 0, "name")
          assert_equal "object", body.dig("tools", 0, "input_schema", "type")
          assert_equal "Be concise", body.dig("system", 0, "text")
          assert_equal({ "type" => "none" }, body["tool_choice"])
        else
          assert_equal "calculate", body.dig("tools", 0, "function", "name")
          assert_equal "system", body.dig("messages", 0, "role")
          assert_equal "none", body["tool_choice"]
          refute body.key?("system")
        end
        token_key = id.start_with?("openai/") ? "max_completion_tokens" : "max_tokens"
        assert_equal 99, body[token_key]
        refute body.key?("apiKey")
        refute req.headers.key?("X-Api-Key")
        refute req.headers.key?("Anthropic-Beta")
        if id.start_with?("anthropic/")
          assert_equal "Bearer cf-test-token", req.headers["Cf-Aig-Authorization"]
          refute req.headers.key?("Authorization")
        else
          assert_equal "Bearer cf-test-token", req.headers["Authorization"]
          assert_equal "test-gateway", req.headers["Cf-Aig-Gateway-Id"]
          refute req.headers.key?("Cf-Aig-Authorization")
        end
        true
      end.to_return(status: 200, body: stream_body(messages_api, wire_model), headers: { "Content-Type" => "text/event-stream" })

      response = adapter.stream(
        "hello", model: model, tools: [ TOOL ], system: "Be concise", max_completion_tokens: 99, tool_choice: "none")
      assert_equal "cloudflare-ai-gateway", response.provider
      assert_equal "gateway", response.api
      assert_equal "blue", response.content.first.text
      assert_equal 10, response.usage[:input]
      assert_equal 2, response.usage[:output]
      assert_requested request
    end
  end

  test "the same adapter can alternate routes without mutating its client" do
    shared = adapter
    PAIRS.take(3).reverse_each do |id, wire_model, endpoint, messages_api|
      stub_request(:post, endpoint).to_return(
        status: 200, body: stream_body(messages_api, wire_model), headers: { "Content-Type" => "text/event-stream" })
      model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: id)
      assert_equal "blue", shared.stream("hello", model: model, max_completion_tokens: 99).content.first.text
    end
    assert_equal ROOT, shared.client.base_endpoint
  end

  test "preserves real DeepSeek errors instead of substituting another model or retrying" do
    request = stub_request(:post, "#{ROOT}/chat/completions").to_return(
      status: 500, body: JSON.generate(success: false, errors: [ { code: 2002, message: "Model execution failed (Error)" } ]))
    model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: "deepseek/deepseek-v4-pro")
    error = assert_raises(LlmGateway::Errors::InternalServerError) do
      adapter.stream("hello", model: model, max_completion_tokens: 99)
    end
    assert_equal 2002, error.code
    assert_includes error.message, "Model execution failed (Error)"
    assert_includes error.message, "deepseek/deepseek-v4-pro"
    assert_includes error.message, "rest_completions"
    assert_requested request, times: 1
  end

  test "proxy requests use the same automatic routing and stream decoding" do
    PAIRS.take(3).each do |id, wire_model, endpoint, messages_api|
      stub_request(:post, endpoint).to_return(
        status: 200, body: stream_body(messages_api, wire_model), headers: { "Content-Type" => "text/event-stream" })
      payload = {
        adapter: "cloudflare-ai-gateway",
        model: id,
        config: { account_id: ACCOUNT_ID, gateway_id: "test-gateway", api_key: "cf-test-token" },
        messages: "hello",
        options: { max_completion_tokens: 99 }
      }
      status, _, body = LlmGateway::Proxy::Server.new.call(
        "REQUEST_METHOD" => "POST", "PATH_INFO" => LlmGateway::Proxy::Server::PATH, "rack.input" => StringIO.new(JSON.generate(payload)))
      assert_equal 200, status
      mapper = LlmGateway::Adapters::CloudflareAIGateway::StreamMapper.new(provider: "cloudflare-ai-gateway", api: "gateway")
      body.each do |frame|
        event = frame.lines.find { |line| line.start_with?("event:") }&.delete_prefix("event:")&.strip
        data = JSON.parse(frame.lines.find { |line| line.start_with?("data:") }.delete_prefix("data:")).deep_symbolize_keys
        mapper.map(event: event, data: data)
      end
      mapper.finish
      assert_equal "blue", mapper.result.content.first.text
    end
  end

  test "catalog routing metadata stays immutable and separate from the public ID" do
    model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: "anthropic/claude-haiku-5.5")
    assert_equal "anthropic/claude-haiku-5-5", model.routing[:canonical_model_id]
    assert_equal "@ai-sdk/anthropic", model.routing[:provider_npm]
    assert_includes model.routing[:provider_api], "/anthropic/v1"
    assert model.routing.frozen?
    assert model.routing.values.all?(&:frozen?)
    assert_raises(ArgumentError) do
      LlmGateway::Models::Definition.new(provider: "test", id: "test", routing: { arbitrary_endpoint: "https://example.com" })
    end
  end

  test "preserves original public adapter entry points" do
    gateway = LlmGateway::Adapters::CloudflareAIGateway
    assert_equal gateway::Gateway, gateway::ChatCompletions
    assert_equal gateway::Gateway, gateway::Messages
    assert_equal gateway::GatewayAdapter, LlmGateway::Proxy::Protocol.load_adapter("cloudflare-ai-gateway")
  end

  private

  def adapter
    LlmGateway::Adapters::CloudflareAIGateway::Gateway.build(
      account_id: ACCOUNT_ID, gateway_id: "test-gateway", api_key: "cf-test-token")
  end

  def stream_body(messages_api, model)
    events = if messages_api
      [
        { type: "message_start", message: { id: "msg_cf", role: "assistant", model: model, usage: { input_tokens: 10 } } },
        { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } },
        { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "blue" } },
        { type: "content_block_stop", index: 0 },
        { type: "message_delta", delta: { stop_reason: "end_turn" }, usage: { output_tokens: 2 } },
        { type: "message_stop" }
      ]
    else
      [
        { id: "chat_cf", model: model, choices: [ { delta: { role: "assistant", content: "blue" } } ] },
        { choices: [ { delta: {}, finish_reason: "stop" } ] },
        { choices: [], usage: { prompt_tokens: 10, completion_tokens: 2 } }
      ]
    end
    events.map { |event| "#{"event: #{event[:type]}\n" if event[:type]}data: #{JSON.generate(event)}\n\n" }.join
  end
end
