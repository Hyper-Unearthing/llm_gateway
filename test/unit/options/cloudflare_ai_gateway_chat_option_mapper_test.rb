# frozen_string_literal: true

require "test_helper"

class CloudflareAIGatewayChatOptionMapperTest < Test
  Mapper = LlmGateway::Adapters::CloudflareAIGateway::ChatOptionMapper

  %w[openai/gpt-5.4-nano deepseek/deepseek-v4-pro].each do |id|
    test "passes mapped managed and native options through the automatic adapter for #{id}" do
      client = FakeClient.new
      adapter = LlmGateway::Adapters::CloudflareAIGateway::GatewayAdapter.new(client)
      model = LlmGateway.models.fetch(provider: "cloudflare-ai-gateway", id: id)
      response = adapter.stream(
        "hello",
        model: model, reasoning: "high", max_completion_tokens: 321,
        response_format: "json_object", temperature: 0.2, top_p: 0.9, seed: 7,
        stream_options: { include_usage: true }, tool_choice: "none")
      token_key = id.start_with?("openai/") ? :max_completion_tokens : :max_tokens
      assert_equal :rest_completions, client.route
      assert_equal id, client.model
      assert_equal "gateway", response.api
      assert_equal({
        token_key => 321,
        reasoning_effort: "high",
        response_format: { type: "json_object" },
        temperature: 0.2,
        top_p: 0.9,
        seed: 7,
        stream_options: { include_usage: true },
        tool_choice: "none"
      }, client.options)
    end
  end

  test "rejects unknown and structural fields" do
    %i[unknown_option apiKey messages tools system stream cache_key cache_retention].each do |key|
      assert_raises(ArgumentError) { Mapper.map(key => true) }
    end
    assert_raises(ArgumentError) { Mapper.map(max_tokens: 10, max_completion_tokens: 10) }
    assert_raises(ArgumentError) { Mapper.map(reasoning_control: { type: :toggle, value: true }) }
  end

  test "preserves provider defaults and validates final output without mutating input" do
    assert_empty Mapper.map({})
    assert_empty Mapper.map(reasoning_control: { type: :none })
    options = {
      model: "deepseek/deepseek-v4-pro",
      max_completion_tokens: 123,
      reasoning_control: { type: :effort, value: "high" },
      tool_choice: { type: "none" }
    }
    original = Marshal.load(Marshal.dump(options))
    mapped = Mapper.map(options)
    assert_equal original, options
    assert_equal({ model: "deepseek/deepseek-v4-pro", max_tokens: 123, reasoning_effort: "high", tool_choice: "none" }, mapped)
    assert_empty mapped.keys - Mapper::VALID_OPTIONS
  end

  class FakeClient < LlmGateway::Clients::CloudflareAIGateway
    attr_reader :options, :model, :route

    def initialize
      super(account_id: "a" * 32, api_key: "test-token")
    end

    def for_route(route)
      @route = route
      self
    end

    def stream(_messages, tools:, system:, model:, **options)
      @model, @options = model, options
      yield({ data: { id: "chat_cf", model: model, choices: [ { delta: { role: "assistant", content: "hello" } } ] } })
      yield({ data: { choices: [ { delta: {}, finish_reason: "stop" } ] } })
      yield({ data: { choices: [], usage: { prompt_tokens: 10, completion_tokens: 2 } } })
    end
  end
end
