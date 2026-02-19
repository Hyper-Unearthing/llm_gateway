# frozen_string_literal: true

require "test_helper"

class ClaudeCodeOAuthFlowTest < Test
  teardown do
    WebMock.reset!
  end

  test "start returns authorization url code verifier and state" do
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new(redirect_uri: "http://127.0.0.1:4000/callback")

    result = flow.start(state: "test-state")

    assert_equal "test-state", result[:state]
    refute_nil result[:code_verifier]
    assert_includes result[:authorization_url], "https://claude.ai/oauth/authorize"
    assert_includes result[:authorization_url], "redirect_uri=http%3A%2F%2F127.0.0.1%3A4000%2Fcallback"
    assert_includes result[:authorization_url], "state=test-state"
  end

  test "parse callback extracts code and state" do
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new

    result = flow.parse_callback("http://127.0.0.1:4000/callback?code=abc123&state=xyz")

    assert_equal "abc123", result[:code]
    assert_equal "xyz", result[:state]
  end

  test "exchange code accepts full callback url" do
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new(redirect_uri: "http://127.0.0.1:4000/callback")

    stub_request(:post, "https://api.anthropic.com/v1/oauth/token")
      .with do |request|
        body = JSON.parse(request.body)
        body["code"] == "abc123" &&
          body["state"] == "xyz" &&
          body["redirect_uri"] == "http://127.0.0.1:4000/callback" &&
          body["code_verifier"] == "verifier"
      end
      .to_return(
        status: 200,
        body: {
          access_token: "access",
          refresh_token: "refresh",
          expires_in: 3600
        }.to_json,
        headers: { 'Content-Type': "application/json" }
      )

    result = flow.exchange_code("http://127.0.0.1:4000/callback?code=abc123&state=xyz", "verifier")

    assert_equal "access", result[:access_token]
    assert_equal "refresh", result[:refresh_token]
    assert_instance_of Time, result[:expires_at]
  end

  test "exchange code still accepts legacy code state format" do
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new

    stub_request(:post, "https://api.anthropic.com/v1/oauth/token")
      .with do |request|
        body = JSON.parse(request.body)
        body["code"] == "abc123" && body["state"] == "xyz"
      end
      .to_return(
        status: 200,
        body: {
          access_token: "access",
          refresh_token: "refresh",
          expires_in: 3600
        }.to_json,
        headers: { 'Content-Type': "application/json" }
      )

    result = flow.exchange_code("abc123#xyz", "verifier")

    assert_equal "access", result[:access_token]
    assert_equal "refresh", result[:refresh_token]
  end

  test "exchange code splits legacy code state format even when state argument is provided" do
    flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new

    stub_request(:post, "https://api.anthropic.com/v1/oauth/token")
      .with do |request|
        body = JSON.parse(request.body)
        body["code"] == "abc123" && body["state"] == "xyz"
      end
      .to_return(
        status: 200,
        body: {
          access_token: "access",
          refresh_token: "refresh",
          expires_in: 3600
        }.to_json,
        headers: { 'Content-Type': "application/json" }
      )

    result = flow.exchange_code("abc123#xyz", "verifier", state: "original-state")

    assert_equal "access", result[:access_token]
    assert_equal "refresh", result[:refresh_token]
  end
end
