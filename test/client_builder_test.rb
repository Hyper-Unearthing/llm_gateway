# frozen_string_literal: true

require "test_helper"

class ClientBuilderTest < Test
  test "builds claude client with api key messages provider" do
    adapter = LlmGateway.build_provider({
      provider: "anthropic_messages",
      api_key: "sk-ant-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Anthropic::MessagesAdapter, adapter
    assert_instance_of LlmGateway::Clients::Anthropic, adapter.client
  end

  test "builds claude client with anthropic messages provider" do
    adapter = LlmGateway.build_provider({
      provider: "anthropic_messages",
      api_key: "sk-ant-oat-test-token"
    })

    assert_instance_of LlmGateway::Adapters::Anthropic::MessagesAdapter, adapter
    assert_instance_of LlmGateway::Clients::Anthropic, adapter.client
  end

  test "builds openai client with default completions adapter" do
    adapter = LlmGateway.build_provider({
      provider: "openai_completions",
      api_key: "sk-openai-test-key"
    })

    assert_instance_of LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::OpenAI, adapter.client
  end

  test "builds openai client with responses api" do
    adapter = LlmGateway.build_provider({
      provider: "openai_responses",
      api_key: "sk-openai-test-key"
    })

    assert_instance_of LlmGateway::Adapters::OpenAI::ResponsesAdapter, adapter
    assert_instance_of LlmGateway::Clients::OpenAI, adapter.client
  end

  test "builds groq client" do
    adapter = LlmGateway.build_provider({
      provider: "groq_completions",
      api_key: "gsk-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::Groq, adapter.client
  end

  test "builds proxy provider" do
    adapter = LlmGateway.build_provider({
      provider: "proxy",
      url: "https://managerbot.example.test",
      target_provider: "openai_responses",
      target_config: { model: "gpt-4.1" }
    })

    assert_instance_of LlmGateway::Proxy::Adapter, adapter
    assert_instance_of LlmGateway::Proxy::Client, adapter.client
    assert_equal "proxy", adapter.provider_key
    assert_equal "openai_responses", adapter.client.target_provider
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
      "provider" => "groq_completions",
      "api_key" => "gsk-test-key"
    })

    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, adapter
    assert_instance_of LlmGateway::Clients::Groq, adapter.client
  end

  test "provider registry exposes built in providers" do
    assert LlmGateway::ProviderRegistry.registered?("anthropic_messages")
    assert LlmGateway::ProviderRegistry.registered?("openai_completions")
    assert LlmGateway::ProviderRegistry.registered?("openai_responses")
    assert LlmGateway::ProviderRegistry.registered?("groq_completions")
    assert LlmGateway::ProviderRegistry.registered?("openai_codex")
  end
end
