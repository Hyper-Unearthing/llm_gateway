# frozen_string_literal: true

require "test_helper"

class ClientBuilderTest < Test
  {
    "anthropic-messages" => [ LlmGateway::Adapters::Anthropic::MessagesAdapter, LlmGateway::Clients::Anthropic ],
    "openai-completions" => [ LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter, LlmGateway::Clients::OpenAI ],
    "openai-responses" => [ LlmGateway::Adapters::OpenAI::ResponsesAdapter, LlmGateway::Clients::OpenAI ],
    "groq-completions" => [ LlmGateway::Adapters::Groq::ChatCompletionsAdapter, LlmGateway::Clients::Groq ],
    "openai-codex" => [ LlmGateway::Adapters::OpenAICodex::ResponsesAdapter, LlmGateway::Clients::OpenAI ]
  }.each do |id, (adapter_class, client_class)|
    test "builds #{id}" do
      adapter = LlmGateway.build_adapter(adapter: id, api_key: "test-key")

      assert_instance_of adapter_class, adapter
      assert_instance_of client_class, adapter.client
      assert_equal id, adapter.adapter_id
      assert_equal LlmGateway::AdapterRegistry.fetch(id)[:provider], adapter.provider
    end
  end

  test "builds proxy adapter without model state" do
    adapter = LlmGateway.build_adapter(
      adapter: "proxy",
      url: "https://managerbot.example.test",
      target_provider: "openai-responses",
      target_config: {}
    )

    assert_instance_of LlmGateway::Proxy::Adapter, adapter
    assert_equal "proxy", adapter.provider
    assert_equal "proxy", adapter.adapter_id
  end

  test "rejects unknown adapters" do
    assert_raises(LlmGateway::Errors::UnsupportedProvider) do
      LlmGateway.build_adapter(adapter: "unknown", api_key: "test-key")
    end
  end

  test "rejects model state" do
    assert_raises(ArgumentError) do
      LlmGateway.build_adapter(adapter: "openai-responses", api_key: "test", model: "gpt-5.4")
    end
  end

  test "registry exposes built-in adapters" do
    %w[anthropic-messages openai-completions openai-responses groq-completions openai-codex proxy].each do |id|
      assert LlmGateway::AdapterRegistry.registered?(id)
    end
  end
end
