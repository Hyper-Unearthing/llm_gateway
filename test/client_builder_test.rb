# frozen_string_literal: true

require "test_helper"

class ClientBuilderTest < Test
  test "builds claude client with api_key auth" do
    adapter = LlmGateway::ClientBuilder.build({
      provider: "anthropic",
      type: "api_key",
      key: "sk-ant-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Claude::MessagesAdapter, adapter
    assert_instance_of LlmGateway::Clients::Claude, adapter.client
  end

  test "builds claude code client with oauth auth" do
    adapter = LlmGateway::ClientBuilder.build({
      provider: "anthropic",
      type: "oauth",
      accessToken: "test-access-token",
      refreshToken: "test-refresh-token",
      expiresAt: (Time.now.to_i + 3600) * 1000
    })

    assert_instance_of LlmGateway::Adapters::ClaudeCode::MessagesAdapter, adapter
    assert_instance_of LlmGateway::Clients::ClaudeCode, adapter.client
  end

  test "builds openai client with default completions adapter" do
    adapter = LlmGateway::ClientBuilder.build({
      provider: "openai",
      type: "api_key",
      key: "sk-openai-test-key"
    })

    assert_instance_of LlmGateway::Adapters::OpenAi::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::OpenAi, adapter.client
  end

  test "builds openai client with completions api" do
    adapter = LlmGateway::ClientBuilder.build({
      provider: "openai",
      type: "api_key",
      key: "sk-openai-test-key",
      api: "completions"
    })

    assert_instance_of LlmGateway::Adapters::OpenAi::ChatCompletionsAdapter, adapter
  end

  test "builds openai client with responses api" do
    adapter = LlmGateway::ClientBuilder.build({
      provider: "openai",
      type: "api_key",
      key: "sk-openai-test-key",
      api: "responses"
    })

    assert_instance_of LlmGateway::Adapters::OpenAi::ResponsesAdapter, adapter
    assert_instance_of LlmGateway::Clients::OpenAi, adapter.client
  end

  test "builds groq client" do
    adapter = LlmGateway::ClientBuilder.build({
      provider: "groq",
      type: "api_key",
      key: "gsk-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::Groq, adapter.client
  end

  test "raises error for unknown provider" do
    assert_raises(LlmGateway::Errors::UnsupportedProvider) do
      LlmGateway::ClientBuilder.build({
        provider: "unknown",
        type: "api_key",
        key: "test-key"
      })
    end
  end

  test "raises error for unknown auth type on anthropic" do
    assert_raises(LlmGateway::Errors::UnsupportedProvider) do
      LlmGateway::ClientBuilder.build({
        provider: "anthropic",
        type: "unknown",
        key: "test-key"
      })
    end
  end

  test "works with string keys" do
    adapter = LlmGateway::ClientBuilder.build({
      "provider" => "groq",
      "type" => "api_key",
      "key" => "gsk-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::Groq, adapter.client
  end
end
