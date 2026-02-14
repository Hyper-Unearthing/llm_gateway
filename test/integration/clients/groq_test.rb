# frozen_string_literal: true

require "test_helper"

class GroqClientTest < Test
  teardown do
    WebMock.reset!
  end

  def stub_error_response(error, status_code = 200)
    stub_request(:post, "https://api.groq.com/openai/v1/chat/completions")
      .to_return(status: status_code,
                 body: {
                   error: error
                 }.to_json,
                 headers: { 'Content-Type': "application/json" })
  end

  def groq_client
    LlmGateway::Clients::Groq.new
  end

  test "throws bad request error" do
    error = assert_raises(LlmGateway::Errors::BadRequestError) do
      VCR.use_cassette(vcr_cassette_name) do
        groq_client.chat([ "i am not a bad" ])
      end
    end
    assert_equal "'messages.0' : value must be an object with the discriminator property: 'role'", error.message
  end

  test "throws authentication error" do
    error = assert_raises(LlmGateway::Errors::AuthenticationError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Clients::Groq.new(api_key: "123").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "Invalid API Key", error.message
  end

  test "throws not found error" do
    error = assert_raises(LlmGateway::Errors::NotFoundError) do
      VCR.use_cassette(vcr_cassette_name) do
        LlmGateway::Clients::Groq.new(model_key: "randomodel").chat([ { 'role': "user", 'content': "hello" } ])
      end
    end
    assert_equal "The model `randomodel` does not exist or you do not have access to it.", error.message
  end

  test "throws rate limit error" do
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      VCR.use_cassette(vcr_cassette_name) do
        groq_client.chat([ { 'role': "user", 'content': "aqklcsa," * 15_000 } ])
      end
    end
    assert_equal "Request too large for model `gemma2-9b-it` in organization `org_01jr5m71qmfspb8essdm2fwc7v` service tier `on_demand` on tokens per minute (TPM): Limit 30000, Requested 30005, please reduce your message size and try again. Need more tokens? Visit https://groq.com/self-serve-support/ to request higher limits.",
                 error.message
  end

  test "throws permission denied error" do
    stub_error_response({ type: "insufficient_quota", message: "access denied" }, 403)
    assert_raises(LlmGateway::Errors::PermissionDeniedError) do
      groq_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end
  test "throws conflict error" do
    stub_error_response({ type: "conflict", message: "resource conflict" }, 409)
    assert_raises(LlmGateway::Errors::ConflictError) do
      groq_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws unprocessable entity error" do
    stub_error_response({ type: "invalid_request_error", message: "validation failed" }, 422)
    assert_raises(LlmGateway::Errors::UnprocessableEntityError) do
      groq_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error" do
    stub_error_response({ type: "server_error" }, 500)
    assert_raises(LlmGateway::Errors::InternalServerError) do
      groq_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws internal server error for 5xx codes" do
    stub_error_response({ type: "server_overloaded" }, 503)
    assert_raises(LlmGateway::Errors::OverloadError) do
      groq_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end

  test "throws API status error for unknown status codes" do
    stub_error_response({ type: "unknown_error", message: "something went wrong" }, 418)
    assert_raises(LlmGateway::Errors::APIStatusError) do
      groq_client.chat([ { 'role': "user", 'content': "hello" } ])
    end
  end
end
