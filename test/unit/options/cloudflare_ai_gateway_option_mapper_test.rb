# frozen_string_literal: true

require "test_helper"

class CloudflareAIGatewayOptionMapperTest < Test
  Mapper = LlmGateway::Adapters::CloudflareAIGateway::OptionMapper

  test "passes mapped managed options and provider-native options through adapter to client" do
    client = FakeClient.new
    adapter = LlmGateway::Adapters::CloudflareAIGateway::ChatCompletionsAdapter.new(client)
    model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: "openai/gpt-5.4-nano")

    response = adapter.stream("hello", model: model, reasoning: "high", max_completion_tokens: 321,
                                       response_format: "json_object", temperature: 0.2, top_p: 0.9, seed: 7,
                                       stream_options: { include_usage: true })

    assert_equal "cloudflare-ai-gateway", response.provider
    assert_equal "completions", response.api
    assert_equal model.id, client.model
    assert_equal({
      max_completion_tokens: 321,
      reasoning_effort: "high",
      response_format: { type: "json_object" },
      temperature: 0.2,
      top_p: 0.9,
      seed: 7,
      stream_options: { include_usage: true }
    }, client.options)
  end

  test "maps managed token limit to max_tokens for non OpenAI upstreams" do
    model = "anthropic/claude-haiku-5-5"
    assert_equal({ model: model, max_tokens: 123 }, Mapper.map(model: model, max_completion_tokens: 123))
    assert_equal({ max_tokens: 42 }, Mapper.map(max_tokens: 42))
    assert_raises(ArgumentError) { Mapper.map(max_tokens: 42, max_completion_tokens: 42) }
  end

  test "preserves provider defaults rather than inheriting OpenAI defaults" do
    assert_empty Mapper.map({})
    assert_empty Mapper.map(reasoning_control: { type: :none })
    assert_equal({ response_format: { type: "text" } }, Mapper.map(response_format: "text"))
    assert_equal({ reasoning_effort: "low" }, Mapper.map(reasoning_effort: "low"))
  end

  test "rejects unsupported managed controls and OpenAI specific options" do
    assert_raises(ArgumentError) { Mapper.map(reasoning_control: { type: :toggle, value: true }) }
    assert_raises(ArgumentError) { Mapper.map(reasoning_control: { type: :budget_tokens, value: 1024 }) }
    %i[unknown_option cache_key cache_retention prompt_cache_retention store apiKey].each do |option|
      error = assert_raises(ArgumentError) { Mapper.map(option => true) }
      assert_includes error.message, option.to_s
    end
  end

  test "does not handle transcript tools system or stream as options" do
    %i[messages tools system stream].each do |option|
      assert_raises(ArgumentError) { Mapper.map(option => []) }
    end
  end

  test "validates the final output and leaves caller options unchanged" do
    options = {
      model: "openai/gpt-5.4-nano",
      max_completion_tokens: 12,
      response_format: { type: "json_schema", json_schema: { name: "answer" } },
      stop: [ "END" ],
      frequency_penalty: 0.2,
      presence_penalty: 0.1,
      tool_choice: "auto",
      parallel_tool_calls: false
    }
    original = Marshal.load(Marshal.dump(options))
    mapped = Mapper.map(options)
    assert_equal original, options
    assert_equal options, mapped
    assert_empty mapped.keys - Mapper::VALID_OPTIONS
  end

  class FakeClient < LlmGateway::Clients::CloudflareAIGateway
    attr_reader :options, :model

    def initialize
      super(account_id: "a" * 32, api_key: "test-key")
    end

    def stream(_messages, tools:, system:, model:, **options)
      @options = options
      @model = model
      yield({ data: { id: "chatcmpl_cf", model: model, choices: [ { delta: { role: "assistant" } } ] } })
      yield({ data: { choices: [ { delta: { content: "hi" } } ] } })
      yield({ data: { choices: [ { finish_reason: "stop" } ] } })
      yield({ data: { choices: [], usage: {} } })
    end
  end
end
