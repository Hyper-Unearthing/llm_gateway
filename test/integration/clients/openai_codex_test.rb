# frozen_string_literal: true

require "test_helper"

class OpenAiCodexClientTest < Test
  CODEX_ENDPOINT = "https://chatgpt.com/backend-api/codex/responses"

  teardown do
    WebMock.reset!
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  def codex_client(access_token: "test-access-token", model_key: "gpt-4o", account_id: "acct_123")
    LlmGateway::Clients::OpenAiCodex.new(
      access_token: access_token,
      model_key: model_key,
      account_id: account_id
    )
  end

  # Build a minimal SSE response that contains a response.completed event.
  def completed_sse_body(response_id: "resp_123", model: "gpt-4o", text: "Hello!", tools: [])
    output = if tools.any?
      tools.map.with_index do |t, i|
        {
          type: "function_call",
          id: "fc_#{i}",
          call_id: t[:call_id] || "call_#{i}",
          name: t[:name],
          arguments: (t[:arguments] || {}).to_json
        }
      end
    else
      [
        {
          type: "message",
          role: "assistant",
          id: "msg_#{response_id}",
          content: [ { type: "output_text", text: text } ]
        }
      ]
    end

    response_obj = {
      id: response_id,
      model: model,
      output: output,
      usage: { input_tokens: 10, output_tokens: 5 }
    }

    "event: response.completed\ndata: #{JSON.generate(response: response_obj)}\n\n"
  end

  def stub_stream_success(**kwargs)
    stub_request(:post, CODEX_ENDPOINT)
      .to_return(
        status: 200,
        body: completed_sse_body(**kwargs),
        headers: { "Content-Type" => "text/event-stream" }
      )
  end

  def stub_error_response(error_hash, status_code)
    stub_request(:post, CODEX_ENDPOINT)
      .to_return(
        status: status_code,
        body: { error: error_hash }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  # ---------------------------------------------------------------------------
  # Basic functionality
  # ---------------------------------------------------------------------------

  test "chat without block returns completed response hash" do
    stub_stream_success(response_id: "resp_abc", text: "Hello!")

    result = codex_client.chat([ { role: "user", content: "Hi" } ])

    assert_equal "resp_abc", result[:id]
    assert_equal "gpt-4o",   result[:model]
    assert result[:output],  "Expected output in response"
    assert result[:usage],   "Expected usage in response"
  end

  test "chat with block yields raw SSE events" do
    stub_stream_success(response_id: "resp_block")

    events = []
    codex_client.chat([ { role: "user", content: "Hi" } ]) { |e| events << e }

    completed = events.find { |e| e[:event] == "response.completed" }
    assert completed, "Expected response.completed event"
    assert_equal "resp_block", completed.dig(:data, :response, :id)
  end

  test "stream yields raw SSE events" do
    stub_stream_success(response_id: "resp_stream")

    events = []
    codex_client.stream([ { role: "user", content: "Hi" } ]) { |e| events << e }

    assert_any_event(events, "response.completed")
  end

  # ---------------------------------------------------------------------------
  # Request body
  # ---------------------------------------------------------------------------

  test "sends required Codex body fields" do
    stub_stream_success

    codex_client.chat([ { role: "user", content: "Hi" } ])

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["stream"]  == true &&
        body["store"] == false &&
        body["include"]&.include?("reasoning.encrypted_content") &&
        body.key?("instructions") &&
        body.key?("input")
    end
  end

  test "passes instructions from system messages" do
    stub_stream_success

    system = [ { type: "text", content: "You are a coder." } ]
    codex_client.chat([ { role: "user", content: "Hi" } ], system: system)

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["instructions"] == "You are a coder."
    end
  end

  test "defaults instructions to helpful assistant when system is empty" do
    stub_stream_success

    codex_client.chat([ { role: "user", content: "Hi" } ], system: [])

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["instructions"] == "You are a helpful assistant."
    end
  end

  test "includes tools when provided" do
    stub_stream_success

    tools = [ { type: "function", name: "get_weather", description: "Get weather", parameters: {} } ]
    codex_client.chat([ { role: "user", content: "Weather?" } ], tools: tools)

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body        = JSON.parse(req.body)
      sent_tools  = body["tools"] || []
      sent_tools.any? { |t| t["name"] == "get_weather" }
    end
  end

  test "includes prompt_cache_key and retention when set" do
    stub_stream_success

    client = codex_client
    client.prompt_cache_key = "my-cache-key"
    client.chat([ { role: "user", content: "Hi" } ])

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["prompt_cache_key"] == "my-cache-key" &&
        body["prompt_cache_retention"] == "24h"
    end
  end

  test "includes reasoning when reasoning_effort is set" do
    stub_stream_success

    client = LlmGateway::Clients::OpenAiCodex.new(
      access_token: "tok",
      reasoning_effort: "medium"
    )
    client.chat([ { role: "user", content: "Hi" } ])

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["reasoning"] == { "effort" => "medium", "summary" => "detailed" }
    end
  end

  test "chat accepts unified reasoning option" do
    stub_stream_success

    codex_client.chat([ { role: "user", content: "Hi" } ], reasoning: { effort: "high" })

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["reasoning"] == { "effort" => "high", "summary" => "detailed" }
    end
  end

  test "stream accepts unified reasoning option" do
    stub_stream_success

    codex_client.stream([ { role: "user", content: "Hi" } ], reasoning: "low") { |_e| }

    assert_requested(:post, CODEX_ENDPOINT) do |req|
      body = JSON.parse(req.body)
      body["reasoning"] == { "effort" => "low", "summary" => "detailed" }
    end
  end

  # ---------------------------------------------------------------------------
  # Headers
  # ---------------------------------------------------------------------------

  test "sends Bearer authorization header" do
    stub_stream_success

    codex_client(access_token: "my-oauth-token").chat([ { role: "user", content: "Hi" } ])

    assert_requested(:post, CODEX_ENDPOINT,
                     headers: { "Authorization" => "Bearer my-oauth-token" })
  end

  test "sends OpenAI-Beta responses=experimental header" do
    stub_stream_success

    codex_client.chat([ { role: "user", content: "Hi" } ])

    assert_requested(:post, CODEX_ENDPOINT,
                     headers: { "OpenAI-Beta" => "responses=experimental" })
  end

  test "sends chatgpt-account-id header when account_id present" do
    stub_stream_success

    codex_client(account_id: "acct_xyz").chat([ { role: "user", content: "Hi" } ])

    assert_requested(:post, CODEX_ENDPOINT,
                     headers: { "chatgpt-account-id" => "acct_xyz" })
  end

  test "omits chatgpt-account-id header when account_id is nil" do
    stub_stream_success

    LlmGateway::Clients::OpenAiCodex.new(access_token: "tok").chat([ { role: "user", content: "Hi" } ])

    assert_not_requested(:post, CODEX_ENDPOINT,
                         headers: { "chatgpt-account-id" => /.*/ })
  end

  # ---------------------------------------------------------------------------
  # Error handling
  # ---------------------------------------------------------------------------

  test "raises AuthenticationError on 401" do
    stub_error_response({ type: "authentication_error", message: "Invalid bearer token" }, 401)

    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      codex_client.chat([ { role: "user", content: "Hi" } ])
    end
    assert_equal "Invalid bearer token", error.message
  end

  test "raises BadRequestError on 400" do
    stub_error_response({ type: "invalid_request_error", message: "Bad input" }, 400)

    error = assert_raises(LlmGateway::Errors::BadRequestError) do
      codex_client.chat([ { role: "user", content: "Hi" } ])
    end
    assert_equal "Bad input", error.message
  end

  test "raises NotFoundError on 404" do
    stub_error_response({ type: "not_found_error", message: "model not found" }, 404)

    assert_raises(LlmGateway::Errors::NotFoundError) do
      codex_client.chat([ { role: "user", content: "Hi" } ])
    end
  end

  test "raises RateLimitError on 429" do
    stub_error_response({ type: "rate_limit_error", message: "rate limit exceeded" }, 429)

    assert_raises(LlmGateway::Errors::RateLimitError) do
      codex_client.chat([ { role: "user", content: "Hi" } ])
    end
  end

  test "raises OverloadError on 503" do
    stub_error_response({ type: "service_unavailable", message: "overloaded" }, 503)

    assert_raises(LlmGateway::Errors::OverloadError) do
      codex_client.chat([ { role: "user", content: "Hi" } ])
    end
  end

  test "raises InternalServerError on 500" do
    stub_error_response({ type: "server_error", message: "internal error" }, 500)

    assert_raises(LlmGateway::Errors::InternalServerError) do
      codex_client.chat([ { role: "user", content: "Hi" } ])
    end
  end

  # ---------------------------------------------------------------------------
  # Token manager
  # ---------------------------------------------------------------------------

  test "creates token manager when refresh_token is provided" do
    stub_request(:post, "https://auth.openai.com/oauth/token")
      .to_return(
        status: 200,
        body: {
          access_token: "new-access-token",
          refresh_token: "new-refresh-token",
          expires_in: 3600
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    # No access_token → eagerly fetches
    client = LlmGateway::Clients::OpenAiCodex.new(refresh_token: "old-refresh-token")

    refute_nil client.token_manager
    assert_equal "new-access-token", client.token_manager.access_token
  end

  test "skips eager refresh when access_token is supplied alongside refresh_token" do
    client = LlmGateway::Clients::OpenAiCodex.new(
      access_token: "existing-token",
      refresh_token: "refresh-token",
      expires_at: Time.now + 3600
    )

    refute_nil client.token_manager
    assert_equal "existing-token", client.token_manager.access_token
  end

  test "retries request after token refresh on AuthenticationError with expired token" do
    token_manager = mock("token_manager")
    token_manager.stubs(:ensure_valid_token)
    token_manager.stubs(:access_token).returns("refreshed-token")
    token_manager.stubs(:account_id).returns(nil)
    token_manager.stubs(:token_expired?).returns(true)
    token_manager.expects(:refresh_access_token!).once

    client = codex_client
    client.instance_variable_set(:@token_manager, token_manager)

    stub_request(:post, CODEX_ENDPOINT).to_return(
      {
        status: 401,
        body: { error: { type: "authentication_error", message: "expired" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      },
      {
        status: 200,
        body: completed_sse_body(response_id: "resp_retry"),
        headers: { "Content-Type" => "text/event-stream" }
      }
    )

    result = client.chat([ { role: "user", content: "Hi" } ])
    assert_equal "resp_retry", result[:id]
  end

  test "does not retry when token is not expired" do
    token_manager = mock("token_manager")
    token_manager.stubs(:ensure_valid_token)
    token_manager.stubs(:access_token).returns("test-token")
    token_manager.stubs(:account_id).returns(nil)
    token_manager.stubs(:token_expired?).returns(false)

    client = codex_client
    client.instance_variable_set(:@token_manager, token_manager)

    stub_error_response({ type: "authentication_error", message: "invalid token" }, 401)

    assert_raises(LlmGateway::Errors::AuthenticationError) do
      client.chat([ { role: "user", content: "Hi" } ])
    end
  end

  test "on_token_refresh= delegates to token_manager" do
    refresh_called = false
    callback = ->(_at, _rt, _exp) { refresh_called = true }

    stub_request(:post, "https://auth.openai.com/oauth/token")
      .to_return(
        status: 200,
        body: {
          access_token: "refreshed",
          refresh_token: "new-rt",
          expires_in: 3600
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    client = LlmGateway::Clients::OpenAiCodex.new(
      access_token: "tok",
      refresh_token: "rt",
      expires_at: Time.now + 3600
    )
    client.on_token_refresh = callback
    client.token_manager.refresh_access_token!

    assert refresh_called, "Expected on_token_refresh callback to be called"
  end

  # ---------------------------------------------------------------------------
  # OAuthFlow constants
  # ---------------------------------------------------------------------------

  test "OAuthFlow has the correct CLIENT_ID" do
    assert_equal "app_EMoamEEZ73f0CkXaXp7hrann",
                 LlmGateway::Clients::OpenAiCodex::OAuthFlow::CLIENT_ID
  end

  test "OAuthFlow start returns authorization_url, code_verifier, and state" do
    flow   = LlmGateway::Clients::OpenAiCodex::OAuthFlow.new
    result = flow.start

    assert result[:authorization_url].start_with?("https://auth.openai.com/oauth/authorize"),
           "Expected OpenAI authorize URL"
    assert result[:code_verifier], "Expected code_verifier"
    assert result[:state],         "Expected state"
  end

  test "OAuthFlow authorization_url includes required params" do
    flow   = LlmGateway::Clients::OpenAiCodex::OAuthFlow.new
    result = flow.start(state: "teststate")
    uri    = URI.parse(result[:authorization_url])
    params = URI.decode_www_form(uri.query).to_h

    assert_equal "code",                         params["response_type"]
    assert_equal "app_EMoamEEZ73f0CkXaXp7hrann", params["client_id"]
    assert_equal "S256",                          params["code_challenge_method"]
    assert_equal "teststate",                    params["state"]
    assert_equal "true",                          params["codex_cli_simplified_flow"]
  end

  # ---------------------------------------------------------------------------
  # TokenManager
  # ---------------------------------------------------------------------------

  test "TokenManager token_expired? returns true when expires_at is nil" do
    tm = LlmGateway::Clients::OpenAiCodex::TokenManager.new(refresh_token: "rt")
    assert tm.token_expired?
  end

  test "TokenManager token_expired? returns false for future expiry" do
    tm = LlmGateway::Clients::OpenAiCodex::TokenManager.new(
      refresh_token: "rt",
      expires_at: Time.now + 3600
    )
    refute tm.token_expired?
  end

  test "TokenManager token_expired? returns true for past expiry" do
    tm = LlmGateway::Clients::OpenAiCodex::TokenManager.new(
      refresh_token: "rt",
      expires_at: Time.now - 1
    )
    assert tm.token_expired?
  end

  test "TokenManager refresh_access_token! updates tokens and fires callback" do
    received = []

    stub_request(:post, "https://auth.openai.com/oauth/token")
      .to_return(
        status: 200,
        body: {
          access_token: "new-at",
          refresh_token: "new-rt",
          expires_in: 7200
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    tm = LlmGateway::Clients::OpenAiCodex::TokenManager.new(
      refresh_token: "old-rt",
      expires_at: Time.now - 1
    )
    tm.on_token_refresh = ->(at, rt, exp) { received << { at: at, rt: rt, exp: exp } }

    tm.refresh_access_token!

    assert_equal "new-at", tm.access_token
    assert_equal "new-rt", tm.refresh_token
    assert_equal 1,        received.size
    assert_equal "new-at", received.first[:at]
  end

  # ---------------------------------------------------------------------------
  # Provider registry
  # ---------------------------------------------------------------------------

  test "openai_oauth_codex is registered in ProviderRegistry" do
    assert LlmGateway::ProviderRegistry.registered?("openai_oauth_codex"),
           "Expected openai_oauth_codex to be registered"
  end

  private

  def assert_any_event(events, event_type)
    found = events.any? { |e| e[:event] == event_type }
    assert found, "Expected to find event '#{event_type}' in #{events.map { |e| e[:event] }.inspect}"
  end
end
