# frozen_string_literal: true

require "test_helper"

class ClaudeCodeClientTest < Test
  teardown do
    WebMock.reset!
  end

  def stub_error_response(error, status_code = 200)
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: status_code,
                 body: {
                   type: "error",
                   error:
                 }.to_json,
                 headers: { 'Content-Type': "application/json" })
  end

  def claude_code_client(access_token: ENV["ANTHROPIC_ACCESS_TOKEN"], model_key: "claude-3-7-sonnet-20250219")
    LlmGateway::Clients::ClaudeCode.new(access_token: access_token, model_key: model_key, refresh_token: ENV["ANTHROPIC_REFRESH_TOKEN"], expires_at: 1771064051861)
  end

  # --- Error handling tests (mirrors Claude client) ---

  test "throws bad request error" do
    error = assert_raises(LlmGateway::Errors::BadRequestError) do
      VCR.use_cassette(vcr_cassette_name) do
        claude_code_client.chat("i am not a list")
      end
    end
    assert_equal "messages: Input should be a valid list", error.message
    assert_equal "invalid_request_error", error.code
  end

  test "works" do
    VCR.use_cassette(vcr_cassette_name) do
      result = claude_code_client.chat([ { 'role': "user", 'content': "aqklcsa," } ])
      assert result[:id], "Expected response to have an id"
      assert result[:content], "Expected response to have content"
    end
  end

  test "throws prompt too long" do
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      VCR.use_cassette(vcr_cassette_name) do
        claude_code_client.chat([ { 'role': "user", 'content': "aqklcsa," * 40_000 } ])
      end
    end
    assert_equal "prompt is too long: 224967 tokens > 200000 maximum", error.message
    assert_equal "invalid_request_error", error.code
  end

  test "throws authentication error" do
    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      VCR.use_cassette(vcr_cassette_name) do
        claude_code_client(access_token: "invalid-token").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "Invalid bearer token", error.message
    assert_equal "authentication_error", error.code
  end

  test "throws not found error" do
    error = assert_raises(LlmGateway::Errors::NotFoundError) do
      VCR.use_cassette(vcr_cassette_name) do
        claude_code_client(model_key: "randomodel").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "model: randomodel", error.message
    assert_equal "not_found_error", error.code
  end

  test "throws permission denied error" do
    stub_error_response({ type: "permission_denied", message: "access denied" }, 403)
    assert_raises(LlmGateway::Errors::PermissionDeniedError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws conflict error" do
    stub_error_response({ type: "conflict", message: "resource conflict" }, 409)
    assert_raises(LlmGateway::Errors::ConflictError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws unprocessable entity error" do
    stub_error_response({ type: "unprocessable_entity", message: "validation failed" }, 422)
    assert_raises(LlmGateway::Errors::UnprocessableEntityError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws rate limit error" do
    stub_error_response({ type: "rate_limit_error" }, 429)
    assert_raises(LlmGateway::Errors::RateLimitError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error" do
    stub_error_response({ type: "internal_server_error" }, 500)
    assert_raises(LlmGateway::Errors::InternalServerError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws overload error for 503" do
    stub_error_response({ type: "service_unavailable" }, 503)
    assert_raises(LlmGateway::Errors::OverloadError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws API status error for unknown status codes" do
    stub_error_response({ type: "unknown_error", message: "something went wrong" }, 418)
    assert_raises(LlmGateway::Errors::APIStatusError) do
      claude_code_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  # --- Tool use ---

  test "supports tool use requests" do
    tools = [ {
      name: "get_weather",
      description: "Get the current weather",
      input_schema: {
        type: "object",
        properties: {
          location: { type: "string", description: "The city name" }
        },
        required: [ "location" ]
      }
    } ]

    expected_response = {
      id: "msg_123",
      model: "claude-3-7-sonnet-20250219",
      content: [ {
        type: "tool_use",
        id: "toolu_123",
        name: "get_weather",
        input: { location: "San Francisco" }
      } ],
      usage: { input_tokens: 100, output_tokens: 50 }
    }

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(body: hash_including(tools: tools))
      .to_return(status: 200, body: expected_response.to_json, headers: { 'Content-Type': "application/json" })

    result = claude_code_client.chat([ { role: "user", content: "What is the weather in San Francisco?" } ], tools: tools)
    assert_equal "msg_123", result[:id]
    assert_equal "tool_use", result[:content][0][:type]
    assert_equal "get_weather", result[:content][0][:name]
  end

  # --- Claude Code specific behavior ---

  test "uses Bearer authorization header" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(headers: { "Authorization" => "Bearer abc" })
      .to_return(status: 200, body: { id: "msg_1", content: [], usage: {} }.to_json,
                 headers: { 'Content-Type': "application/json" })

    claude_code_client(access_token: "abc").chat([ { role: "user", content: "hello" } ])

    assert_requested(:post, "https://api.anthropic.com/v1/messages",
                     headers: { "Authorization" => "Bearer abc" })
  end

  test "sends claude code specific headers" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(status: 200, body: { id: "msg_1", content: [], usage: {} }.to_json,
                 headers: { 'Content-Type': "application/json" })

    claude_code_client.chat([ { role: "user", content: "hello" } ])

    assert_requested(:post, "https://api.anthropic.com/v1/messages",
                     headers: {
                       "anthropic-beta" => "claude-code-20250219,oauth-2025-04-20",
                       "anthropic-dangerous-direct-browser-access" => "true",
                       "x-app" => "cli"
                     })
  end

  test "prepends claude code identity system prompt" do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with { |request|
        body = JSON.parse(request.body)
        system = body["system"]
        system.is_a?(Array) &&
          system.length == 1 &&
          system[0]["type"] == "text" &&
          system[0]["text"] == "You are Claude Code, Anthropic's official CLI for Claude."
      }
      .to_return(status: 200, body: { id: "msg_1", content: [], usage: {} }.to_json,
                 headers: { 'Content-Type': "application/json" })

    claude_code_client.chat([ { role: "user", content: "hello" } ])
  end

  test "prepends claude code identity to existing system prompts" do
    custom_system = [ { type: "text", text: "You are a helpful assistant." } ]

    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with { |request|
        body = JSON.parse(request.body)
        system = body["system"]
        system.is_a?(Array) &&
          system.length == 2 &&
          system[0]["text"] == "You are Claude Code, Anthropic's official CLI for Claude." &&
          system[1]["text"] == "You are a helpful assistant."
      }
      .to_return(status: 200, body: { id: "msg_1", content: [], usage: {} }.to_json,
                 headers: { 'Content-Type': "application/json" })

    claude_code_client.chat([ { role: "user", content: "hello" } ], system: custom_system)
  end

  test "strips claude_code/ prefix from model key" do
    client = LlmGateway::Clients::ClaudeCode.new(
      access_token: "test-token",
      model_key: "claude_code/claude-3-7-sonnet-20250219"
    )
    assert_equal "claude-3-7-sonnet-20250219", client.model_key
  end

  # --- Token refresh tests ---

  test "refreshes token on authentication error when token is expired" do
    token_manager = mock("token_manager")
    token_manager.stubs(:ensure_valid_token)
    token_manager.stubs(:access_token).returns("new-token")
    token_manager.stubs(:token_expired?).returns(true)
    token_manager.expects(:refresh_access_token).once

    client = claude_code_client
    client.instance_variable_set(:@token_manager, token_manager)

    # First call returns 401, second succeeds
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .to_return(
        {
          status: 401,
          body: { type: "error", error: { type: "authentication_error", message: "invalid token" } }.to_json,
          headers: { 'Content-Type': "application/json" }
        },
        {
          status: 200,
          body: { id: "msg_1", content: [], usage: {} }.to_json,
          headers: { 'Content-Type': "application/json" }
        }
      )

    result = client.chat([ { role: "user", content: "hello" } ])
    assert_equal "msg_1", result[:id]
  end

  test "does not retry on authentication error when token is not expired" do
    token_manager = mock("token_manager")
    token_manager.stubs(:ensure_valid_token)
    token_manager.stubs(:access_token).returns("test-token")
    token_manager.stubs(:token_expired?).returns(false)

    client = claude_code_client
    client.instance_variable_set(:@token_manager, token_manager)

    stub_error_response({ type: "authentication_error", message: "invalid token" }, 401)

    assert_raises(LlmGateway::Errors::AuthenticationError) do
      client.chat([ { role: "user", content: "hello" } ])
    end
  end

  test "does not retry on authentication error when no token manager" do
    stub_error_response({ type: "authentication_error", message: "invalid token" }, 401)

    assert_raises(LlmGateway::Errors::AuthenticationError) do
      claude_code_client.chat([ { role: "user", content: "hello" } ])
    end
  end

  test "initializes with refresh token and creates token manager" do
    # Stub the token refresh endpoint
    stub_request(:post, "https://api.anthropic.com/v1/oauth/token")
      .to_return(status: 200, body: {
        access_token: "new-access-token",
        refresh_token: "new-refresh-token",
        expires_in: 3600
      }.to_json, headers: { 'Content-Type': "application/json" })

    client = LlmGateway::Clients::ClaudeCode.new(
      refresh_token: "test-refresh-token",
      client_id: "test-client-id",
      client_secret: "test-client-secret"
    )

    refute_nil client.token_manager
    assert_equal "new-access-token", client.token_manager.access_token
  end

  test "skips token refresh when access token provided with refresh token" do
    client = LlmGateway::Clients::ClaudeCode.new(
      access_token: "existing-access-token",
      refresh_token: "test-refresh-token",
      expires_at: Time.now + 3600,
      client_id: "test-client-id",
      client_secret: "test-client-secret"
    )

    refute_nil client.token_manager
    assert_equal "existing-access-token", client.token_manager.access_token
  end
end
