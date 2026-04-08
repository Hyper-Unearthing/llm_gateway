# frozen_string_literal: true

require "test_helper"

class OpenaiClientTest < Test
  teardown do
    WebMock.reset!
  end

  def mapped_chat_options(**options)
    LlmGateway::Adapters::OpenAI::ChatCompletions::OptionMapper.map(options)
  end

  def stub_error_response(error, status_code = 200)
    stub_request(:post, "https://api.openai.com/v1/chat/completions")
      .to_return(status: status_code,
                 body: {
                   error: error
                 }.to_json,
                 headers: { 'Content-Type': "application/json" })
  end

  def openai_client
    LlmGateway::Clients::OpenAI.new
  end

  test "throws bad request error" do
    error = assert_raises(LlmGateway::Errors::BadRequestError) do
      VCR.use_cassette(vcr_cassette_name) do
        openai_client.chat([ "i am not a bad" ], **mapped_chat_options(max_completion_tokens: 4096))
      end
    end
    assert_equal "Invalid type for 'messages[0]': expected an object, but got a string instead.", error.message
  end

  test "throws authentication error" do
    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Clients::OpenAI.new(api_key: "123").chat([ { 'role': "user", 'content': "hello" } ], **mapped_chat_options(max_completion_tokens: 4096))
      end
    end
    assert_equal "Incorrect API key provided: <BEARER_TOKEN>. You can find your API key at https://platform.openai.com/account/api-keys.",
                 error.message
  end

  test "throws not found error" do
    error = assert_raises(LlmGateway::Errors::NotFoundError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Clients::OpenAI.new(model_key: "randomodel").chat([ { 'role': "user", 'content': "hello" } ], **mapped_chat_options(max_completion_tokens: 4096))
      end
    end
    assert_equal "The model `randomodel` does not exist or you do not have access to it.", error.message
  end

  test "embeddings api" do
    VCR.use_cassette(vcr_cassette_name) do
      response = LlmGateway::Clients::OpenAI.new(model_key: "text-embedding-3-small").generate_embeddings("hello world")
      assert(response[:usage], prompt_tokens: 2, total_tokens: 2)
      assert(response[:object], "list")
      assert(response[:model], "text-embedding-3-small")
      assert(response[:object], "list")
      assert(response[:data].first[:embedding].length, 1536)
    end
  end

  test "throws rate limit error" do
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      VCR.use_cassette(vcr_cassette_name) do
        openai_client.chat([ { 'role': "user", 'content': "aqklcsa," * 100_000 } ], **mapped_chat_options(max_completion_tokens: 4096))
      end
    end
    assert_includes error.message, "Request too large for"
  end

  test "throws permission denied error" do
    stub_error_response({ type: "insufficient_quota", message: "access denied" }, 403)
    assert_raises(LlmGateway::Errors::PermissionDeniedError) do
      openai_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws conflict error" do
    stub_error_response({ type: "conflict", message: "resource conflict" }, 409)
    assert_raises(LlmGateway::Errors::ConflictError) do
      openai_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws unprocessable entity error" do
    stub_error_response({ type: "invalid_request_error", message: "validation failed" }, 422)
    assert_raises(LlmGateway::Errors::UnprocessableEntityError) do
      openai_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error" do
    stub_error_response({ type: "server_error" }, 500)
    assert_raises(LlmGateway::Errors::InternalServerError) do
      openai_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error for 5xx codes" do
    stub_error_response({ type: "server_overloaded" }, 503)
    assert_raises(LlmGateway::Errors::OverloadError) do
      openai_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws API status error for unknown status codes" do
    stub_error_response({ type: "unknown_error", message: "something went wrong" }, 418)
    assert_raises(LlmGateway::Errors::APIStatusError) do
      openai_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "get_oauth_access_token returns existing non-expired codex token" do
    token = openai_client.get_oauth_access_token(
      access_token: "valid-token",
      refresh_token: "refresh-token",
      expires_at: Time.now + 3600
    )

    assert_equal "valid-token", token
  end

  test "get_oauth_access_token refreshes expired codex token and fires callback" do
    callback_payload = nil

    stub_request(:post, "https://auth.openai.com/oauth/token")
      .to_return(
        status: 200,
        body: {
          access_token: "new-access-token",
          refresh_token: "new-refresh-token",
          expires_in: 3600
        }.to_json,
        headers: { 'Content-Type': "application/json" }
      )

    token = openai_client.get_oauth_access_token(
      access_token: "expired-token",
      refresh_token: "refresh-token",
      expires_at: Time.now - 60
    ) do |access_token, refresh_token, expires_at|
      callback_payload = {
        access_token: access_token,
        refresh_token: refresh_token,
        expires_at: expires_at
      }
    end

    assert_equal "new-access-token", token
    assert_equal "new-access-token", callback_payload[:access_token]
    assert_equal "new-refresh-token", callback_payload[:refresh_token]
    assert callback_payload[:expires_at].is_a?(Time)
  end

  test "chat_codex routes through codex endpoint" do
    stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
      .to_return(
        status: 200,
        body: "event: response.completed\ndata: #{JSON.generate(response: { id: "resp_1", model: "gpt-4o", output: [], usage: {} })}\n\n",
        headers: { "Content-Type" => "text/event-stream" }
      )

    result = LlmGateway::Clients::OpenAI.new(api_key: "oauth-token").chat_codex([ { role: "user", content: "hello" } ])

    assert_equal "resp_1", result[:id]
  end

  test "stream_codex yields codex SSE events" do
    stub_request(:post, "https://chatgpt.com/backend-api/codex/responses")
      .to_return(
        status: 200,
        body: "event: response.completed\ndata: #{JSON.generate(response: { id: "resp_stream", model: "gpt-4o", output: [], usage: {} })}\n\n",
        headers: { "Content-Type" => "text/event-stream" }
      )

    events = []
    LlmGateway::Clients::OpenAI.new(api_key: "oauth-token").stream_codex([ { role: "user", content: "hello" } ]) { |e| events << e }

    assert events.any? { |e| e[:event] == "response.completed" }
  end
end
