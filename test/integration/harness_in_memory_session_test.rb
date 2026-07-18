# frozen_string_literal: true

require "test_helper"
require "llm_gateway/agents/harness"
require "llm_gateway/agents/in_memory_session_manager"

class HarnessInMemorySessionIntegrationTest < Test
  class TestHarness < LlmGateway::Agents::Harness
    TOOLS = []
  end

  class AddTool < LlmGateway::Tool
    name "add"
    description "Adds two numbers"
    input_schema({ type: "object" })

    def execute(input, tool_use_id:)
      tool_result(input.fetch(:left) + input.fetch(:right), tool_use_id: tool_use_id)
    end
  end

  class ToolHarness < LlmGateway::Agents::Harness
    TOOLS = [ AddTool ]
  end

  class FakeAdapter
    attr_reader :provider, :calls

    def initialize(responses, provider: "openai")
      @responses = responses.dup
      @provider = provider
      @calls = []
    end

    def resolve_model!(model)
      raise LlmGateway::Errors::ModelProviderMismatch unless model.provider == provider

      LlmGateway.models.fetch(provider: model.provider, id: model.id)
    end

    def stream(messages, model:, **options)
      resolve_model!(model)
      @calls << { messages: Marshal.load(Marshal.dump(messages)), model: model, options: options }
      if block_given?
        yield AssistantStreamEvent.new(
          type: :text_delta,
          content_index: 0,
          delta: "streamed",
          partial: PartialAssistantMessage.new(timestamp: 1_716_650_000_000)
        )
      end
      @responses.shift || HarnessInMemorySessionIntegrationTest.assistant_message("fallback")
    end
  end

  OPENAI_MODEL = LlmGateway.models.fetch("openai/gpt-5.4")
  OTHER_OPENAI_MODEL = LlmGateway.models.fetch("openai/gpt-5.1")
  ANTHROPIC_MODEL = LlmGateway.models.fetch("anthropic/claude-sonnet-4-20250514")

  def self.assistant_message(text, content: nil, stop_reason: "stop")
    AssistantMessage.new(
      id: "msg_#{text.gsub(/\W+/, "_")}",
      model: "fake-model",
      usage: { input: 1, output: 2, total: 3 },
      role: "assistant",
      timestamp: 1_716_650_000_000,
      stop_reason: stop_reason,
      provider: "openai",
      api: "responses",
      content: content || [ { type: "text", text: text } ]
    )
  end

  def assistant_message(...)
    self.class.assistant_message(...)
  end

  def user_message(text)
    { role: "user", content: [ { type: "text", text: text } ] }
  end

  def new_harness(responses, harness_class: TestHarness, model: OPENAI_MODEL)
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    session.change_model(model)
    adapter = FakeAdapter.new(responses)
    [ harness_class.new(session, adapter: adapter), session, adapter ]
  end

  test "session persists provider and model primitives and rehydrates the catalog object" do
    session = LlmGateway::Agents::InMemorySessionManager.new("session")

    session.change_model(OPENAI_MODEL)
    event = session.events.last

    assert_equal "model_change", event[:type]
    assert_equal "openai", event[:provider]
    assert_equal "gpt-5.4", event[:model_id]
    assert_same OPENAI_MODEL, session.current_configuration.model
  end

  test "session supports model IDs containing slashes and walks backward to latest configuration" do
    session = LlmGateway::Agents::InMemorySessionManager.new("session")
    groq_model = LlmGateway.models.fetch(provider: "groq", id: "openai/gpt-oss-120b")

    session.change_model(OPENAI_MODEL)
    session.change_reasoning("low")
    session.push_message(user_message("between"))
    session.change_model(groq_model)
    session.change_reasoning("medium")

    configuration = session.current_configuration
    assert_same groq_model, configuration.model
    assert_equal "medium", configuration.reasoning
    assert_equal "openai/gpt-oss-120b", session.events.last(2).first[:model_id]
  end

  test "session rejects unknown persisted models" do
    session = LlmGateway::Agents::InMemorySessionManager.new("session")

    session.push_entry(type: "model_change", provider: "openai", model_id: "missing")
    assert_raises(KeyError) { session.current_configuration }
  end

  test "harness receives an adapter and streams the session model" do
    harness, session, adapter = new_harness([ assistant_message("hello back") ])

    result = harness.prompt_message(user_message("hello"))

    assert_equal "hello back", result.content.first.text
    assert_same adapter, harness.adapter
    refute_respond_to harness, :provider
    assert_same OPENAI_MODEL, adapter.calls.first[:model]
    assert_equal "high", adapter.calls.first[:options][:reasoning]
    assert_equal [ "user", "assistant" ], session.active_messages.map { |message| message[:role] }
  end

  test "harness forwards constructor and updated cache settings during agent runs" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    session.change_model(OPENAI_MODEL)
    adapter = FakeAdapter.new([ assistant_message("cached"), assistant_message("updated") ])
    harness = TestHarness.new(
      session,
      adapter: adapter,
      cache_key: "session-123",
      cache_retention: "long"
    )

    harness.prompt_message(user_message("hello"))

    assert_equal "session-123", adapter.calls.first[:options][:cache_key]
    assert_equal "long", adapter.calls.first[:options][:cache_retention]

    harness.cache_key = "session-456"
    harness.cache_retention = "short"
    harness.prompt_message(user_message("again"))

    assert_equal "session-456", adapter.calls.last[:options][:cache_key]
    assert_equal "short", adapter.calls.last[:options][:cache_retention]
  end

  test "harness persists model and reasoning changes without adapter selection" do
    harness, session, adapter = new_harness([ assistant_message("ok") ])

    harness.model = OTHER_OPENAI_MODEL
    harness.reasoning = "low"
    harness.prompt_message(user_message("hello"))

    assert_same OTHER_OPENAI_MODEL, adapter.calls.first[:model]
    assert_equal "low", adapter.calls.first[:options][:reasoning]
    model_event = session.events.reverse.find { |event| event[:type] == "model_change" }
    assert_equal({ provider: "openai", model_id: "gpt-5.1" }, model_event.slice(:provider, :model_id))
  end

  test "harness changes compatible adapters without a model event" do
    harness, session, = new_harness([])
    replacement = FakeAdapter.new([])
    event_count = session.events.length

    assert_same replacement, harness.change_adapter(replacement)
    assert_same replacement, harness.adapter
    assert_equal event_count, session.events.length
  end

  test "harness requires an adapter and model together when changing providers" do
    harness, session, = new_harness([])
    anthropic = FakeAdapter.new([], provider: "anthropic")

    assert_raises(LlmGateway::Errors::ModelProviderMismatch) { harness.change_adapter(anthropic) }
    assert_same anthropic, harness.change_adapter(anthropic, model: ANTHROPIC_MODEL)
    assert_same ANTHROPIC_MODEL, session.current_configuration.model
    assert_same anthropic, harness.adapter
  end

  test "harness emits lifecycle and tool events and continues after a tool call" do
    tool_message = assistant_message(
      "tool",
      content: [ { id: "toolu_add", type: "tool_use", name: "add", input: { left: 2, right: 3 } } ],
      stop_reason: "tool_use"
    )
    harness, session, adapter = new_harness(
      [ tool_message, assistant_message("5") ],
      harness_class: ToolHarness
    )
    event_types = []

    result = harness.prompt_message(user_message("add")) { |event| event_types << event.type }

    assert_equal "5", result.content.first.text
    assert_equal 2, adapter.calls.length
    assert_includes event_types, :tool_execution_start
    assert_includes event_types, :tool_execution_end
    tool_result = session.active_messages.find { |message| message.dig(:content, 0, :type) == "tool_result" }
    assert_equal 5, tool_result.dig(:content, 0, :content)
  end

  test "queued follow-up messages are drained after the current turn" do
    harness, _session, adapter = new_harness([ assistant_message("first"), assistant_message("second") ])
    queued = false

    harness.prompt_message(user_message("start")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      harness.follow_up_message(user_message("next"))
    end

    assert_equal 2, adapter.calls.length
    assert_equal "next", adapter.calls.last[:messages][-1].dig(:content, 0, :text)
  end
end
