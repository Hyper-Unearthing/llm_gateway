# frozen_string_literal: true

require "test_helper"

class CloudflareAIGatewayTest < Test
  ACCOUNT_ID = "a" * 32
  ENDPOINT = "https://gateway.ai.cloudflare.com/v1/#{ACCOUNT_ID}/default/compat/chat/completions"

  test "authenticates using only Cloudflare credentials for unified billing" do
    client = LlmGateway::Clients::CloudflareAIGateway.new(account_id: ACCOUNT_ID, gateway_id: "default", api_key: "test-cf-token")
    request = stub_request(:post, ENDPOINT).with do |req|
      body = JSON.parse(req.body)
      req.headers["Cf-Aig-Authorization"] == "Bearer test-cf-token" &&
        !req.headers.key?("Authorization") && !body.key?("apiKey") &&
        body == { "model" => "openai/gpt-5.4-nano", "messages" => [ { "role" => "user", "content" => "hi" } ], "max_tokens" => 8 }
    end.to_return(status: 200, body: '{"choices":[]}', headers: { "Content-Type" => "application/json" })

    client.chat([ { role: "user", content: "hi" } ], model: "openai/gpt-5.4-nano", max_tokens: 8)
    assert_requested request
  end

  test "validates endpoint path components" do
    [ nil, "", "../wrong", "a" * 31, "g" * 32 ].each do |id|
      assert_raises(ArgumentError) { LlmGateway::Clients::CloudflareAIGateway.new(account_id: id) }
    end
    [ "", "../wrong", "my/gateway", "a" * 65 ].each do |id|
      assert_raises(ArgumentError) do
        LlmGateway::Clients::CloudflareAIGateway.new(account_id: ACCOUNT_ID, gateway_id: id)
      end
    end
  end

  test "accepts explicit account gateway and token configuration through the public definition" do
    adapter = LlmGateway::Adapters::CloudflareAIGateway::ChatCompletions.build(
      account_id: ACCOUNT_ID, gateway_id: "my-gateway", api_key: "test-token")
    assert_instance_of LlmGateway::Clients::CloudflareAIGateway, adapter.client
    definition = LlmGateway::Adapters::CloudflareAIGateway::ChatCompletions.definition
    assert_equal "cloudflare-ai-gateway", definition.provider
    assert_equal definition.adapter_class, LlmGateway::Proxy::Protocol.load_adapter("cloudflare-ai-gateway")
    assert_equal "cloudflare-ai-gateway", LlmGateway::Proxy::Protocol.dump_adapter(definition)
  end

  test "catalog contains generated gateway models without custom registration" do
    model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: "openai/gpt-5.4-nano")
    assert_equal :models_dev, model.source
    assert_operator model.context_window, :>, 0
    assert_operator model.max_output_tokens, :>, 0
    refute_nil model.pricing
    assert LlmGateway::Adapters::CloudflareAIGateway::ChatCompletions.supports_model?(model)
    upstream = LlmGateway.models.fetch(provider: "openai", id: "gpt-5.4-nano")
    refute LlmGateway::Adapters::CloudflareAIGateway::ChatCompletions.supports_model?(upstream)
  end

  test "preserves structured Cloudflare errors and standard HTTP error types" do
    client = LlmGateway::Clients::CloudflareAIGateway.new(account_id: ACCOUNT_ID, gateway_id: "default", api_key: "bad-token")
    stub_request(:post, ENDPOINT).to_return(status: 401,
                                            body: JSON.generate(success: false, errors: [ { code: 10000, message: "Authentication error" } ]))
    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      client.chat([], model: "openai/gpt-5.4-nano")
    end
    assert_equal "Authentication error", error.message
    assert_equal 10000, error.code
  end
end
