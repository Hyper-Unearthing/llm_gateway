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

    def execute(input)
      input.fetch(:left) + input.fetch(:right)
    end
  end

  class ExplodingTool < LlmGateway::Tool
    name "explode"
    description "Raises an error"
    input_schema({ type: "object" })

    def execute(_input)
      raise "boom"
    end
  end

  class ToolHarness < LlmGateway::Agents::Harness
    TOOLS = [ AddTool, ExplodingTool ]
  end

  class KwargRecordingHarness < ToolHarness
    TOOLS = ToolHarness::TOOLS

    attr_reader :execute_tool_kwargs

    private

    def execute_tool(tool_class, tool_input, **kwargs)
      @execute_tool_kwargs = kwargs
      super
    end
  end

  FakeInnerClient = Struct.new(:model_key)

  class FakeAdapter
    attr_reader :client, :calls

    def initialize(responses)
      @client = FakeInnerClient.new("fake-model")
      @responses = responses.dup
      @calls = []
    end

    def stream(messages, **options)
      @calls << { messages: Marshal.load(Marshal.dump(messages)), options: options }
      if block_given?
        yield AssistantStreamEvent.new(
          type: :text_delta,
          content_index: 0,
          delta: "streamed",
          partial: PartialAssistantMessage.new(timestamp: 1_716_650_000_000)
        )
      end
      @responses.shift || assistant_message("fallback")
    end
  end

  def assistant_message(text, total_tokens: 10, id: nil)
    assistant_message_with_content(
      [ { type: "text", text: text } ],
      total_tokens: total_tokens,
      id: id || "msg_#{text.gsub(/\W+/, "_")}",
      stop_reason: "stop"
    )
  end

  def assistant_tool_message(tool_name, input, id: nil, tool_use_id: nil)
    assistant_message_with_content(
      [ { id: tool_use_id || "toolu_#{tool_name}", type: "tool_use", name: tool_name, input: input } ],
      id: id || "msg_tool_#{tool_name}",
      stop_reason: "tool_use"
    )
  end

  def assistant_message_with_content(content, total_tokens: 10, id:, stop_reason:)
    AssistantMessage.new(
      id: id,
      model: "fake-model",
      usage: { input_tokens: 1, output_tokens: 2, total_tokens: total_tokens },
      role: "assistant",
      timestamp: 1_716_650_000_000,
      stop_reason: stop_reason,
      provider: "fake",
      api: "fake",
      content: content
    )
  end

  def user_message(text)
    { role: "user", content: [ { type: "text", text: text } ] }
  end

  def stored_assistant_message(text, total_tokens: 10, id: nil)
    stored_message(assistant_message(text, total_tokens: total_tokens, id: id))
  end

  def stored_message(message)
    message.to_h
  end

  def compacted_assistant_message(text, total_tokens: 10, id: nil)
    stored_assistant_message(text, total_tokens: total_tokens, id: id)
  end

  def new_harness(responses, harness_class: TestHarness, model: nil)
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    adapter = FakeAdapter.new(responses)
    [ harness_class.new(session, provider: adapter, model: model), session, adapter ]
  end

  test "creates an in-memory session with a session event and adds messages directly when active" do
    harness, session, client = new_harness([ assistant_message("hello back") ])

    harness.prompt_message(user_message("hello"))

    assert_equal "test-session", session.session_id
    assert_equal "session", session.events.first[:type]
    assert_equal "test-session", session.events.first[:id]
    assert_equal [ user_message("hello") ], client.calls.first[:messages]
    assert_equal [ user_message("hello"), stored_assistant_message("hello back") ], session.active_messages
  end

  test "accepts and normalizes string-keyed LLM-shaped messages" do
    harness, session, client = new_harness([ assistant_message("hello back") ])
    input = {
      "role" => "user",
      "content" => [ { "type" => "text", "text" => "hello" } ]
    }

    harness.prompt_message(input)

    assert_equal [ user_message("hello") ], client.calls.first[:messages]
    assert_equal [ user_message("hello"), stored_assistant_message("hello back") ], session.active_messages
  end

  test "accepts an LLM-shaped content array including images" do
    harness, session, client = new_harness([ assistant_message("image answer") ])
    message = {
      role: "user",
      content: [
        { type: "text", text: "What do you see in this image?" },
        { type: "image", data: "image_b64", media_type: "image/png" }
      ]
    }

    harness.prompt_message(message)

    assert_equal [ message ], client.calls.first[:messages]
    assert_equal [ message, stored_assistant_message("image answer") ], session.active_messages
  end

  test "emits harness events in lifecycle order while streaming" do
    harness, _session, = new_harness([ assistant_message("hello back") ])
    events = []

    harness.prompt_message(user_message("hello")) { |event| events << event.type }

    assert_equal [
      :agent_start,
      :turn_start,
      :message_start,
      :message_update,
      :message_end,
      :turn_end,
      :agent_end
    ], events
  end

  test "accepts model and reasoning options at initialization" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    adapter = FakeAdapter.new([ assistant_message("hello back") ])
    harness = TestHarness.new(
      session,
      provider: adapter,
      model: "initial-model",
      reasoning: "low"
    )

    harness.prompt_message(user_message("hello"))

    assert_equal "initial-model", harness.model
    assert_equal "low", harness.reasoning
    assert_equal adapter, harness.provider
    assert_equal "initial-model", adapter.calls.first[:options][:model]
    assert_equal "low", adapter.calls.first[:options][:reasoning]
  end

  test "initialization publishes model and reasoning events when there is no transcript" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    adapter = FakeAdapter.new([])

    TestHarness.new(session, provider: adapter, model: "initial-model", reasoning: "low")

    model_event = session.events.find { |entry| entry[:type] == "model_change" }
    reasoning_event = session.events.find { |entry| entry[:type] == "reasoning_change" }
    assert_equal "initial-model", model_event[:model_id]
    assert_equal "low", reasoning_event[:reasoning]
    assert model_event[:id]
    assert reasoning_event[:id]
    assert_equal session.events.first[:id], model_event[:parent_id]
    assert_equal model_event[:id], reasoning_event[:parent_id]
  end

  test "session reports last model and reasoning by walking back configuration events" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")

    session.push_entry(type: "model_change", model_id: "first-model")
    session.push_entry(type: "reasoning_change", reasoning: "low")
    session.push_message(user_message("existing"))
    session.push_entry(type: "model_change", model_id: "last-model")
    session.push_entry(type: "reasoning_change", reasoning: "high")

    assert_equal "last-model", session.last_model_used
    assert_equal "high", session.last_reasoning_level_used
  end

  test "initialization does not publish model and reasoning events when transcript matches" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    adapter = FakeAdapter.new([])
    session.push_entry(type: "model_change", model_id: "initial-model")
    session.push_entry(type: "reasoning_change", reasoning: "low")
    session.push_message(user_message("existing"))
    events_before = session.events.dup

    TestHarness.new(session, provider: adapter, model: "initial-model", reasoning: "low")

    assert_equal events_before, session.events
  end

  test "initialization does not publish model and reasoning events when transcript already has configuration" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    adapter = FakeAdapter.new([])
    session.push_entry(type: "model_change", model_id: "old-model")
    session.push_entry(type: "reasoning_change", reasoning: "low")
    session.push_message(user_message("existing"))
    events_before = session.events.dup

    TestHarness.new(session, provider: adapter, model: "new-model", reasoning: "high")

    assert_equal events_before, session.events
  end

  test "loaded transcript with different model and reasoning does not publish duplicate configuration events" do
    session = LlmGateway::Agents::InMemorySessionManager.new("test-session")
    adapter = FakeAdapter.new([ assistant_message("hello back") ])
    session.push_entry(type: "model_change", model_id: "transcript-model")
    session.push_entry(type: "reasoning_change", reasoning: "low")
    session.push_message(user_message("existing"))
    events_before = session.events.dup

    harness = TestHarness.new(session, provider: adapter, model: "configured-model", reasoning: "high")
    harness.prompt_message(user_message("next"))

    assert_equal events_before, session.events.first(events_before.length)
    assert_equal 1, session.events.count { |entry| entry[:type] == "model_change" }
    assert_equal 1, session.events.count { |entry| entry[:type] == "reasoning_change" }
    assert_equal "configured-model", adapter.calls.first[:options][:model]
    assert_equal "high", adapter.calls.first[:options][:reasoning]
  end

  test "publishes model changes to the session and uses the model for streaming" do
    harness, session, client = new_harness([ assistant_message("hello back") ], model: "fake-model")

    harness.model = "fake-model-2"
    harness.model = "fake-model-2"
    harness.prompt_message(user_message("hello"))

    event = session.events.reverse.find { |entry| entry[:type] == "model_change" }
    assert_equal "fake-model-2", harness.model
    assert_equal "model_change", event[:type]
    assert_equal "fake-model-2", event[:model_id]
    assert event[:id]
    assert event[:timestamp]
    assert_equal 2, session.events.count { |entry| entry[:type] == "model_change" }
    assert_equal "fake-model-2", client.calls.first[:options][:model]
  end

  test "publishes reasoning changes to the session and uses the level for streaming" do
    harness, session, client = new_harness([ assistant_message("hello back") ])

    harness.reasoning = "medium"
    harness.reasoning = "medium"
    harness.prompt_message(user_message("hello"))

    event = session.events.reverse.find { |entry| entry[:type] == "reasoning_change" }
    assert_equal "medium", harness.reasoning
    assert_equal "reasoning_change", event[:type]
    assert_equal "medium", event[:reasoning]
    assert event[:id]
    assert event[:timestamp]
    assert_equal 2, session.events.count { |entry| entry[:type] == "reasoning_change" }
    assert_equal "medium", client.calls.first[:options][:reasoning]
  end

  test "queues prompt messages as follow up by default and drains all queued messages together" do
    harness, session, client = new_harness([
      assistant_message("first response", id: "assistant_1"),
      assistant_message("second response", id: "assistant_2")
    ])

    queued = false
    harness.prompt_message(user_message("first")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      harness.prompt_message(user_message("queued one"))
      harness.prompt_message(user_message("queued two"))
    end

    assert_equal 2, client.calls.size
    assert_equal [ user_message("first") ], client.calls[0][:messages]
    assert_equal [
      user_message("first"),
      stored_assistant_message("first response", id: "assistant_1"),
      user_message("queued one"),
      user_message("queued two")
    ], client.calls[1][:messages]

    assert_equal [ "first", "first response", "queued one", "queued two", "second response" ],
      session.active_messages.map { |message| message.dig(:content, 0, :text) }
  end

  test "allows changing the default busy prompt queue" do
    harness, _session, client = new_harness([
      assistant_message("first response", id: "assistant_1"),
      assistant_message("follow up response", id: "assistant_2")
    ])
    harness.default_queue_mode = :follow_up

    queued = false
    harness.prompt_message(user_message("first")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      harness.prompt_message(user_message("queued prompt"))
    end

    assert_equal 2, client.calls.size
    assert_equal [
      user_message("first"),
      stored_assistant_message("first response", id: "assistant_1"),
      user_message("queued prompt")
    ], client.calls[1][:messages]
  end

  test "enqueues a new prompt then continues queued work in queue order" do
    harness, session, client = new_harness([
      assistant_message("combined response", id: "assistant_1")
    ])

    session.push_message_to_queue(user_message("queued steer"), :steer)
    session.push_message_to_queue(user_message("queued follow up one"), :follow_up)
    session.push_message_to_queue(user_message("queued follow up two"), :follow_up)
    session.push_message_to_queue(user_message("queued follow up"), :follow_up)

    harness.prompt_message(user_message("new prompt"))

    assert_equal 1, client.calls.size
    assert_equal [
      user_message("queued steer"),
      user_message("queued follow up one"),
      user_message("queued follow up two"),
      user_message("queued follow up"),
      user_message("new prompt")
    ], client.calls[0][:messages]
  end

  test "does not drain queued messages before enqueueing a prompt while busy" do
    harness, session, client = new_harness([
      assistant_message("first response", id: "assistant_1"),
      assistant_message("second response", id: "assistant_2"),
      assistant_message("third response", id: "assistant_3")
    ])

    queued = false
    harness.prompt_message(user_message("first")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      session.push_message_to_queue(user_message("queued steer"), :steer)
      session.push_message_to_queue(user_message("queued follow up"), :follow_up)

      harness.prompt_message(user_message("busy prompt"))

      assert_equal 0, client.calls.size
      assert_equal [ user_message("first") ], session.active_messages
      assert session.queued_messages?(:steer)
      assert session.queued_messages?(:follow_up)
    end
  end

  test "symbolizes string-keyed messages when draining queued prompts" do
    harness, _session, client = new_harness([
      assistant_message("first response", id: "assistant_1"),
      assistant_message("follow up response", id: "assistant_2")
    ])
    harness.default_queue_mode = :follow_up
    string_keyed_message = {
      "role" => "user",
      "content" => [ { "type" => "text", "text" => "queued prompt" } ]
    }

    queued = false
    harness.prompt_message(user_message("first")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      harness.prompt_message(string_keyed_message)
    end

    assert_equal [
      user_message("first"),
      stored_assistant_message("first response", id: "assistant_1"),
      user_message("queued prompt")
    ], client.calls[1][:messages]
  end

  test "can drain follow up queue one at a time" do
    harness, _session, client = new_harness([
      assistant_message("first response", id: "assistant_1"),
      assistant_message("second response", id: "assistant_2"),
      assistant_message("third response", id: "assistant_3")
    ])
    harness.queue_drain_mode = :one_at_a_time

    queued = false
    harness.prompt_message(user_message("first")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      harness.follow_up_message(user_message("queued one"))
      harness.follow_up_message(user_message("queued two"))
    end

    assert_equal 3, client.calls.size
    assert_equal [
      user_message("first"),
      stored_assistant_message("first response", id: "assistant_1"),
      user_message("queued one")
    ], client.calls[1][:messages]
    assert_equal [
      user_message("first"),
      stored_assistant_message("first response", id: "assistant_1"),
      user_message("queued one"),
      stored_assistant_message("second response", id: "assistant_2"),
      user_message("queued two")
    ], client.calls[2][:messages]
  end

  test "steer messages queued while busy are added before the next model request" do
    tool_request = assistant_tool_message("missing", {}, id: "assistant_missing", tool_use_id: "toolu_1")
    final_response = assistant_message("handled", id: "assistant_final")
    harness, _session, client = new_harness([ tool_request, final_response ], harness_class: ToolHarness)

    queued = false
    harness.prompt_message(user_message("use a missing tool")) do |event|
      next if queued || event.type != :message_end

      queued = true
      harness.steer_message(user_message("please be concise"))
    end

    assert_equal [
      user_message("use a missing tool"),
      stored_message(tool_request),
      tool_result_message("toolu_1", "Unknown tool: missing"),
      user_message("please be concise")
    ], client.calls[1][:messages]
  end

  test "run drains follow up queues after the tool loop completes" do
    tool_request = assistant_tool_message("add", { left: 2, right: 3 }, id: "assistant_tool", tool_use_id: "toolu_add")
    harness, session, client = new_harness([
      tool_request,
      assistant_message("final response", id: "assistant_final"),
      assistant_message("follow up response", id: "assistant_follow_up")
    ], harness_class: ToolHarness)

    session.push_message(user_message("first"))
    session.push_message_to_queue(user_message("follow up"), :follow_up)

    harness.run

    assert_equal 3, client.calls.size
    assert_equal [
      user_message("first"),
      stored_message(tool_request),
      tool_result_message("toolu_add", 5)
    ], client.calls[1][:messages]
    assert_equal [
      user_message("first"),
      stored_message(tool_request),
      tool_result_message("toolu_add", 5),
      stored_assistant_message("final response", id: "assistant_final"),
      user_message("follow up")
    ], client.calls[2][:messages]
    refute session.queued_messages?(:follow_up)
  end

  test "continue drains queued work and starts the agent" do
    harness, session, client = new_harness([
      assistant_message("combined response", id: "assistant_1")
    ])

    session.push_message(user_message("first"))
    session.push_message_to_queue(user_message("queued steer"), :steer)
    session.push_message_to_queue(user_message("queued follow up"), :follow_up)

    harness.continue do |event|
      assert session.busy? if event.type == :agent_start
    end

    assert_equal 1, client.calls.size
    assert_equal [
      user_message("first"),
      user_message("queued steer"),
      user_message("queued follow up")
    ], client.calls[0][:messages]
    refute session.queued_messages?(:steer)
    refute session.queued_messages?(:follow_up)
    assert session.idle?
  end

  test "continue raises when the agent is busy" do
    harness, session, client = new_harness([
      assistant_message("unused", id: "assistant_1")
    ])
    session.busy!
    session.push_message_to_queue(user_message("queued follow up"), :follow_up)

    error = assert_raises(RuntimeError) { harness.continue }

    assert_equal "Cannot continue a busy agent", error.message
    assert_empty client.calls
    assert session.queued_messages?(:follow_up)
    assert session.busy?
  end

  test "follow up messages queued while busy drain together" do
    harness, _session, client = new_harness([
      assistant_message("first response", id: "assistant_1"),
      assistant_message("follow up response", id: "assistant_2"),
      assistant_message("follow up response 2", id: "assistant_3")
    ])

    queued = false
    harness.prompt_message(user_message("first")) do |event|
      next if queued || event.type != :agent_start

      queued = true
      harness.follow_up_message(user_message("follow up"))
      harness.follow_up_message(user_message("follow up"))
    end

    assert_equal 2, client.calls.size
    assert_equal [
      user_message("first"),
      stored_assistant_message("first response", id: "assistant_1"),
      user_message("follow up"),
      user_message("follow up")
    ], client.calls[1][:messages]
  end

  def tool_result_message(tool_use_id, content)
    { role: "user", content: [ { type: "tool_result", tool_use_id: tool_use_id, content: content } ] }
  end

  test "preserves Anthropic tool_result blocks in the follow-up user message" do
    tool_request = assistant_tool_message("missing", {}, id: "assistant_missing", tool_use_id: "toolu_1")
    final_response = assistant_message("handled", id: "assistant_final")
    harness, session, client = new_harness([ tool_request, final_response ], harness_class: ToolHarness)

    harness.prompt_message(user_message("use a missing tool"))

    expected_tool_result = tool_result_message("toolu_1", "Unknown tool: missing")
    assert_equal [
      user_message("use a missing tool"),
      stored_message(tool_request),
      expected_tool_result
    ], client.calls[1][:messages]
    assert_equal expected_tool_result, session.active_messages[2]
  end

  test "passes persisted assistant message session event when executing tools" do
    tool_request = assistant_tool_message("add", { left: 2, right: 3 }, id: "assistant_add", tool_use_id: "toolu_add")
    final_response = assistant_message("handled", id: "assistant_final")
    harness, session = new_harness([ tool_request, final_response ], harness_class: KwargRecordingHarness)

    harness.prompt_message(user_message("use tools"))

    session_event = harness.execute_tool_kwargs[:session_event]
    assert_equal session.events.find { |event| event.dig(:data, :id) == "assistant_add" }, session_event
    assert_equal "message", session_event[:type]
    assert_equal stored_message(tool_request), session_event[:data]
  end

  test "executes tools, records tool results, emits tool events, and continues until a final answer" do
    add_request = assistant_tool_message("add", { left: 2, right: 3 }, id: "assistant_add", tool_use_id: "toolu_add")
    unknown_request = assistant_tool_message("missing", {}, id: "assistant_missing", tool_use_id: "toolu_missing")
    error_request = assistant_tool_message("explode", {}, id: "assistant_error", tool_use_id: "toolu_error")
    final_response = assistant_message("all tools handled", id: "assistant_final")
    harness, session, client = new_harness(
      [ add_request, unknown_request, error_request, final_response ],
      harness_class: ToolHarness
    )
    events = []

    harness.prompt_message(user_message("use tools")) { |event| events << event }

    assert_equal 4, client.calls.size
    assert_equal [ AddTool.definition, ExplodingTool.definition ], client.calls.first[:options][:tools]
    assert_equal [ user_message("use tools") ], client.calls[0][:messages]
    assert_equal [ user_message("use tools"), stored_message(add_request), tool_result_message("toolu_add", 5) ],
      client.calls[1][:messages]
    assert_equal [
      user_message("use tools"),
      stored_message(add_request),
      tool_result_message("toolu_add", 5),
      stored_message(unknown_request),
      tool_result_message("toolu_missing", "Unknown tool: missing")
    ], client.calls[2][:messages]
    assert_equal [
      user_message("use tools"),
      stored_message(add_request),
      tool_result_message("toolu_add", 5),
      stored_message(unknown_request),
      tool_result_message("toolu_missing", "Unknown tool: missing"),
      stored_message(error_request),
      tool_result_message("toolu_error", "Error executing tool: boom")
    ], client.calls[3][:messages]

    tool_start_events = events.grep(LlmGateway::Agents::Event::ToolExecutionStart)
    tool_end_events = events.grep(LlmGateway::Agents::Event::ToolExecutionEnd)
    assert_equal [ "add", "missing", "explode" ], tool_start_events.map { |event| event.attributes.dig(:parameters, :name) }
    assert_equal [ 5, "Unknown tool: missing", "Error executing tool: boom" ],
      tool_end_events.map { |event| event.attributes.dig(:result, :content) }
    assert_equal [
      user_message("use tools"),
      stored_message(add_request),
      tool_result_message("toolu_add", 5),
      stored_message(unknown_request),
      tool_result_message("toolu_missing", "Unknown tool: missing"),
      stored_message(error_request),
      tool_result_message("toolu_error", "Error executing tool: boom"),
      stored_message(final_response)
    ], session.active_messages
  end

  test "tracks event parent relationships and returns events up to a requested event" do
    _harness, session, = new_harness([])

    session.push_message(user_message("one"))
    second = session.push_message(assistant_message("two").to_h)
    session.push_message(user_message("three"))

    assert_nil session.events.first[:parent_id]
    session.events.each_cons(2) do |parent, child|
      assert_equal parent[:id], child[:parent_id]
    end

    second_index = session.events.index(second)
    assert_equal session.events[0..second_index], session.events_until(second[:id])
    assert_equal session.events.last[:id], session.last_message_id
  end

  test "raises when requested event does not exist" do
    _harness, session, = new_harness([])

    error = assert_raises(ArgumentError) { session.events_until("missing-event") }
    assert_equal "Event not found in session: missing-event", error.message
  end

  test "returns active messages after compaction and builds model input with compaction message" do
    harness, session, client = new_harness([
      assistant_message("large response", total_tokens: LlmGateway::Agents::Harness::COMPACTION_TOKEN_THRESHOLD + 1),
      assistant_message("summary of earlier conversation", id: "summary"),
      assistant_message("after compaction", id: "after")
    ])

    harness.prompt_message(user_message("make this large"))
    assert_equal "message", session.events.last[:type]

    harness.prompt_message(user_message("new question"))

    compaction_entry = session.events.find { |entry| entry[:type] == "compaction" }
    assert_equal compacted_assistant_message("summary of earlier conversation", id: "summary"), compaction_entry[:data]
    assert_equal [ user_message("new question"), stored_assistant_message("after compaction", id: "after") ], session.active_messages
    assert_equal [
      compacted_assistant_message("summary of earlier conversation", id: "summary"),
      user_message("new question"),
      stored_assistant_message("after compaction", id: "after")
    ], harness.transcript

    assert_equal [ user_message("make this large"), stored_assistant_message("large response", total_tokens: LlmGateway::Agents::Harness::COMPACTION_TOKEN_THRESHOLD + 1) ],
      client.calls[1][:messages]
    assert_equal "Summarize the conversation so far for future context.", client.calls[1][:options][:system]
  end

  test "compacts before next user message when last assistant message is older than one hour" do
    harness, session, client = new_harness([
      assistant_message("old response"),
      assistant_message("summary after idle", id: "summary"),
      assistant_message("after idle compaction", id: "after")
    ])

    harness.prompt_message(user_message("first question"))
    session.events.last[:timestamp] = (Time.now - LlmGateway::Agents::Harness::COMPACTION_IDLE_THRESHOLD_SECONDS - 1).iso8601

    harness.prompt_message(user_message("second question"))

    compaction_entry = session.events.find { |entry| entry[:type] == "compaction" }
    assert_equal compacted_assistant_message("summary after idle", id: "summary"), compaction_entry[:data]
    assert_equal [ user_message("second question"), stored_assistant_message("after idle compaction", id: "after") ], session.active_messages
    assert_equal [ user_message("first question"), stored_assistant_message("old response") ], client.calls[1][:messages]
    assert_equal "Summarize the conversation so far for future context.", client.calls[1][:options][:system]
  end

  test "tracks total tokens from latest usage" do
    _harness, session, = new_harness([])

    assert_equal 0, session.total_tokens
    session.push_message(assistant_message("small", total_tokens: 42).to_h)
    session.push_message(user_message("no usage"))
    assert_equal 42, session.total_tokens
    session.push_message(assistant_message("larger", total_tokens: 123).to_h)
    assert_equal 123, session.total_tokens
  end
end
