# frozen_string_literal: true

require "test_helper"

class AdapterBuilderTest < Test
  class CustomClient
    attr_reader :api_key

    def initialize(api_key:)
      @api_key = api_key
    end
  end

  class CustomAdapter < LlmGateway::Adapters::Adapter
    provider "custom"
    client_class CustomClient
  end

  class InheritedCustomAdapter < CustomAdapter
  end

  class ProviderOverrideCustomAdapter < CustomAdapter
    provider "custom-override"
  end

  {
    "anthropic-messages" => [ LlmGateway::Adapters::Anthropic::MessagesAdapter, LlmGateway::Clients::Anthropic ],
    "openai-completions" => [ LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter, LlmGateway::Clients::OpenAI ],
    "openai-responses" => [ LlmGateway::Adapters::OpenAI::ResponsesAdapter, LlmGateway::Clients::OpenAI ],
    "groq-completions" => [ LlmGateway::Adapters::Groq::ChatCompletionsAdapter, LlmGateway::Clients::Groq ],
    "openai-codex" => [ LlmGateway::Adapters::OpenAICodex::ResponsesAdapter, LlmGateway::Clients::OpenAI ]
  }.each do |id, (adapter_class, client_class)|
    test "builds #{id}" do
      adapter = adapter_class.build(api_key: "test-key")

      assert_instance_of adapter_class, adapter
      assert_instance_of client_class, adapter.client
      assert_equal adapter_class.provider, adapter.provider
      assert_equal adapter_class, LlmGateway::Proxy::Protocol.load_adapter(id)
    end
  end

  test "adapter classes build without registration or string IDs" do
    adapter = CustomAdapter.build(api_key: "secret")

    assert_instance_of CustomAdapter, adapter
    assert_instance_of CustomClient, adapter.client
    assert_equal "secret", adapter.client.api_key
    assert_equal "custom", adapter.provider
  end

  test "adapter declarations are inherited by subclasses" do
    adapter = InheritedCustomAdapter.build(api_key: "secret")

    assert_instance_of InheritedCustomAdapter, adapter
    assert_instance_of CustomClient, adapter.client
    assert_equal "custom", adapter.provider
  end

  test "subclasses can override an inherited declaration" do
    adapter = ProviderOverrideCustomAdapter.build(api_key: "secret")

    assert_instance_of CustomClient, adapter.client
    assert_equal "custom-override", adapter.provider
    assert_equal "custom", CustomAdapter.provider
  end

  test "built-in adapter classes provide a build shortcut" do
    adapter = LlmGateway::Adapters::OpenAI::ResponsesAdapter.build(api_key: "test-key")

    assert_instance_of LlmGateway::Adapters::OpenAI::ResponsesAdapter, adapter
  end

  test "public definitions build adapters without exposing construction details" do
    definitions = {
      LlmGateway::Adapters::Anthropic::Messages => LlmGateway::Adapters::Anthropic::MessagesAdapter,
      LlmGateway::Adapters::OpenAI::ChatCompletions => LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter,
      LlmGateway::Adapters::OpenAI::Responses => LlmGateway::Adapters::OpenAI::ResponsesAdapter,
      LlmGateway::Adapters::Groq::ChatCompletions => LlmGateway::Adapters::Groq::ChatCompletionsAdapter,
      LlmGateway::Adapters::OpenAICodex::Responses => LlmGateway::Adapters::OpenAICodex::ResponsesAdapter
    }

    definitions.each do |definition, adapter_class|
      adapter = definition.build(api_key: "test-key")

      assert_instance_of adapter_class, adapter
      assert_same adapter_class, definition.adapter_class
      assert definition.definition.frozen?
    end

    definition = LlmGateway::Adapters::OpenAI::Responses.definition
    assert_equal "openai", definition.provider
    assert_equal LlmGateway::Clients::OpenAI, definition.client_class

    model = LlmGateway.models.fetch("openai/gpt-5.4")
    assert LlmGateway::Adapters::OpenAI::Responses.supports_model?(model)
    assert_same model, LlmGateway::Adapters::OpenAI::Responses.model_for_provider_model_key("gpt-5.4")
  end

  test "builds proxy adapter without model state" do
    adapter = LlmGateway::Proxy.build(
      url: "https://managerbot.example.test",
      adapter: LlmGateway::Adapters::OpenAI::Responses,
      target_config: {}
    )

    assert_instance_of LlmGateway::Proxy::Adapter, adapter
    assert_equal "proxy", adapter.provider
    assert_same LlmGateway::Adapters::OpenAI::ResponsesAdapter, adapter.client.adapter_class
  end

  test "proxy stream requires a model" do
    adapter = LlmGateway::Proxy.build(
      url: "https://managerbot.example.test",
      adapter: LlmGateway::Adapters::OpenAI::Responses,
      target_config: {}
    )

    error = assert_raises(ArgumentError) { adapter.stream("hello") }

    assert_match(/missing keyword: :model/, error.message)
  end

  test "rejects unknown adapter names at proxy boundaries" do
    assert_raises(LlmGateway::Errors::UnsupportedProvider) do
      LlmGateway::Proxy::Protocol.load_adapter("unknown")
    end
  end

  test "rejects model state" do
    assert_raises(ArgumentError) do
      LlmGateway::Adapters::OpenAI::Responses.build(api_key: "test", model: "gpt-5.4")
    end
  end

  test "proxy protocol maps built-in adapters in both directions" do
    %w[anthropic-messages openai-completions openai-responses groq-completions openai-codex].each do |name|
      adapter_class = LlmGateway::Proxy::Protocol.load_adapter(name)

      assert_equal name, LlmGateway::Proxy::Protocol.dump_adapter(adapter_class)
    end
  end
end
