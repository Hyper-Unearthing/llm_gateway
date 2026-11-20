# frozen_string_literal: true

require "test_helper"

class StreamMapperErrorsTest < Test
  test "OpenAI stream overloads preserve diagnostics as typed overload errors" do
    openai_mappers.each do |mapper|
      message = "Our servers are currently overloaded. Please try again later."
      error = assert_raises(LlmGateway::Errors::OverloadError) do
        mapper.map(event: "error", data: { type: "error", code: "server_is_overloaded", message: message })
      end
      assert_equal "server_is_overloaded", error.code
      assert_equal message, error.message
    end
  end

  test "nested OpenAI stream overloads are typed too" do
    openai_mappers.each do |mapper|
      error = assert_raises(LlmGateway::Errors::OverloadError) do
        mapper.map(data: { error: { code: "server_is_overloaded", message: "request failed" } })
      end
      assert_equal "server_is_overloaded", error.code
    end
  end

  test "unknown stream errors are not classified by overload prose" do
    openai_mappers.each do |mapper|
      error = assert_raises(LlmGateway::Errors::APIStatusError) do
        mapper.map(event: "error", data: { code: "invalid_request_error", message: "server overloaded" })
      end
      assert_equal "invalid_request_error", error.code
    end
  end

  test "Anthropic stream overloads retain their existing classification" do
    mapper = LlmGateway::Adapters::Anthropic::StreamMapper.new(provider: "anthropic", api: "messages")
    error = assert_raises(LlmGateway::Errors::OverloadError) do
      mapper.map(event: "error", data: { error: { type: "overloaded_error", message: "Overloaded" } })
    end
    assert_equal "overloaded_error", error.code
  end

  private

  def openai_mappers
    [
      LlmGateway::Adapters::OpenAI::Responses::StreamMapper.new(provider: "openai", api: "responses"),
      LlmGateway::Adapters::OpenAI::ChatCompletions::StreamMapper.new(provider: "openai", api: "chat_completions")
    ]
  end
end
