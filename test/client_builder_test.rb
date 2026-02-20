# frozen_string_literal: true

require "test_helper"

class ClientBuilderTest < Test
  test "builds claude client with api key messages provider" do
    adapter = LlmGateway.build_provider({
      provider: "anthropic_apikey_messages",
      api_key: "sk-ant-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Claude::MessagesAdapter, adapter
    assert_instance_of LlmGateway::Clients::Claude, adapter.client
  end

  test "builds claude code client with oauth messages provider" do
    adapter = LlmGateway.build_provider({
      provider: "anthropic_oauth_messages",
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: Time.now + 3600
    })

    assert_instance_of LlmGateway::Adapters::ClaudeCode::MessagesAdapter, adapter
    assert_instance_of LlmGateway::Clients::ClaudeCode, adapter.client
  end

  test "builds openai client with default completions adapter" do
    adapter = LlmGateway.build_provider({
      provider: "openai_apikey_completions",
      api_key: "sk-openai-test-key"
    })

    assert_instance_of LlmGateway::Adapters::OpenAi::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::OpenAi, adapter.client
  end

  test "builds openai client with responses api" do
    adapter = LlmGateway.build_provider({
      provider: "openai_apikey_responses",
      api_key: "sk-openai-test-key"
    })

    assert_instance_of LlmGateway::Adapters::OpenAi::ResponsesAdapter, adapter
    assert_instance_of LlmGateway::Clients::OpenAi, adapter.client
  end

  test "builds groq client" do
    adapter = LlmGateway.build_provider({
      provider: "groq_apikey_completions",
      api_key: "gsk-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::Groq, adapter.client
  end

  test "raises error for unknown provider" do
    assert_raises(LlmGateway::Errors::UnsupportedProvider) do
      LlmGateway.build_provider({
        provider: "unknown_provider",
        api_key: "test-key"
      })
    end
  end

  test "works with string keys" do
    adapter = LlmGateway.build_provider({
      "provider" => "groq_apikey_completions",
      "api_key" => "gsk-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::Groq, adapter.client
  end

  test "provider registry exposes built in providers" do
    assert LlmGateway::ProviderRegistry.registered?("anthropic_apikey_messages")
    assert LlmGateway::ProviderRegistry.registered?("anthropic_oauth_messages")
    assert LlmGateway::ProviderRegistry.registered?("openai_apikey_completions")
    assert LlmGateway::ProviderRegistry.registered?("openai_apikey_responses")
    assert LlmGateway::ProviderRegistry.registered?("groq_apikey_completions")
  end
end
