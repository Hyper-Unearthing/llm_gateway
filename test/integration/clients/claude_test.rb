# frozen_string_literal: true

require "test_helper"

class ClaudeClientTest < Minitest::Test
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

  def claude_client
    LlmGateway::Adapters::Claude::Client.new
  end

  test "throws bad request error" do
    error = assert_raises(LlmGateway::Errors::BadRequestError) do
      VCR.use_cassette(vcr_cassette_name) do
        claude_client.chat("i am not a list")
      end
    end
    assert_equal "messages: Input should be a valid list", error.message
    assert_equal "invalid_request_error", error.code
  end

  test "throws throws prompt too long " do
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      VCR.use_cassette(vcr_cassette_name) do
        claude_client.chat([ { 'role': "user", 'content': "aqklcsa," * 40_000 } ])
      end
    end
    assert_equal "prompt is too long: 224996 tokens > 200000 maximum", error.message
    assert_equal "invalid_request_error", error.code
  end

  test "throws authentication error" do
    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Adapters::Claude::Client.new(api_key: "123").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "invalid x-api-key", error.message
    assert_equal "authentication_error", error.code
  end

  test "throws not found error" do
    error = assert_raises(LlmGateway::Errors::NotFoundError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Adapters::Claude::Client.new(model_key: "randomodel").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "model: randomodel", error.message
    assert_equal "not_found_error", error.code
  end

  test "throws permission denied error" do
    stub_error_response({ type: "permission_denied", message: "access denied" }, 403)
    assert_raises(LlmGateway::Errors::PermissionDeniedError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws conflict error" do
    stub_error_response({ type: "conflict", message: "resource conflict" }, 409)
    assert_raises(LlmGateway::Errors::ConflictError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws unprocessable entity error" do
    stub_error_response({ type: "unprocessable_entity", message: "validation failed" }, 422)
    assert_raises(LlmGateway::Errors::UnprocessableEntityError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws rate limit error" do
    stub_error_response({ type: "rate_limit_error" }, 429)
    assert_raises(LlmGateway::Errors::RateLimitError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error" do
    stub_error_response({ type: "internal_server_error" }, 500)
    assert_raises(LlmGateway::Errors::InternalServerError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error for 5xx codes" do
    stub_error_response({ type: "service_unavailable" }, 503)
    assert_raises(LlmGateway::Errors::OverloadError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws API status error for unknown status codes" do
    stub_error_response({ type: "unknown_error", message: "something went wrong" }, 418)
    assert_raises(LlmGateway::Errors::APIStatusError) do
      claude_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

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
      model: "claude-3-sonnet-20240229",
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

    result = claude_client.chat("What is the weather in San Francisco?", tools: tools)
    assert_equal "msg_123", result[:id]
    assert_equal "tool_use", result[:content][0][:type]
    assert_equal "get_weather", result[:content][0][:name]
  end
end
