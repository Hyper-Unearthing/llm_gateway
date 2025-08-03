# frozen_string_literal: true

require "test_helper"

class OpenaiClientTest < Minitest::Test
  teardown do
    WebMock.reset!
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
    LlmGateway::Adapters::OpenAi::Client.new
  end

  test "throws bad request error" do
    error = assert_raises(LlmGateway::Errors::BadRequestError) do
      VCR.use_cassette(vcr_cassette_name) do
        openai_client.chat([ "i am not a bad" ])
      end
    end
    assert_equal "Invalid type for 'messages[0]': expected an object, but got a string instead.", error.message
  end

  test "throws authentication error" do
    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Adapters::OpenAi::Client.new(api_key: "123").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "Incorrect API key provided: <BEARER_TOKEN>. You can find your API key at https://platform.openai.com/account/api-keys.",
                 error.message
  end

  test "throws not found error" do
    error = assert_raises(LlmGateway::Errors::NotFoundError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Adapters::OpenAi::Client.new(model_key: "randomodel").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "The model `randomodel` does not exist or you do not have access to it.", error.message
  end

  test "embeddings api" do
    VCR.use_cassette(vcr_cassette_name) do
      response = LlmGateway::Adapters::OpenAi::Client.new(model_key: "text-embedding-3-small").generate_embeddings("hello world")
      assert(response[:usage], prompt_tokens: 2, total_tokens: 2)
      assert(response[:object], "list")
      assert(response[:model], "text-embedding-3-small")
      assert(response[:object], "list")
      assert(response[:data].first[:embedding].length, 1536)
    end
  end

  test "throws rate limit error" do
    error = assert_raises(LlmGateway::Errors::RateLimitError) do
      VCR.use_cassette(vcr_cassette_name) do
        openai_client.chat([ { 'role': "user", 'content': "aqklcsa," * 15_000 } ])
      end
    end
    assert_equal "Request too large for gpt-4o in organization org-dqNN3UJQeaIK1sswLJZkvMks on tokens per min (TPM): Limit 30000, Requested 30002. The input or output tokens must be reduced in order to run successfully. Visit https://platform.openai.com/account/rate-limits to learn more.",
                 error.message
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
end
