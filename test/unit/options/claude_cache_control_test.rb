# frozen_string_literal: true

require "test_helper"

class ClaudeCacheControlTest < Test
  test "when cache retention is passed it adds cache_control to last system and tool blocks and sets top-level cache_control" do
    client = LlmGateway::Clients::Anthropic.new(model_key: "claude-3", api_key: "test")

    body = client.send(
      :build_body,
      [
        { role: "user", content: [ { type: "text", text: "hello" }, { type: "text", text: "world" } ] },
        { role: "assistant", content: [ { type: "text", text: "ok" } ] },
        { role: "user", content: [ { type: "text", text: "final" }, { type: "text", text: "question" } ] }
      ],
      system: [
        { type: "text", text: "system 1" },
        { type: "text", text: "system 2" }
      ],
      tools: [
        { name: "tool_1", description: "Tool 1", input_schema: { type: "object", properties: {} } },
        { name: "tool_2", description: "Tool 2", input_schema: { type: "object", properties: {} } }
      ],
      cache_retention: "short"
    )

    expected_cache_control = { type: "ephemeral" }

    assert_equal expected_cache_control, body[:cache_control]

    assert_nil body[:system][0][:cache_control]
    assert_equal expected_cache_control, body[:system][1][:cache_control]

    assert_nil body[:tools][0][:cache_control]
    assert_equal expected_cache_control, body[:tools][1][:cache_control]

    last_user_message = body[:messages].reverse.find { |message| message[:role] == "user" }
    last_user_cache_control_count = Array(last_user_message[:content]).count do |block|
      block[:cache_control] == expected_cache_control
    end

    assert_equal 0, last_user_cache_control_count
  end

  test "uses ttl for long retention on official anthropic base url" do
    client = LlmGateway::Clients::Anthropic.new(model_key: "claude-3", api_key: "test")

    body = client.send(
      :build_body,
      [ { role: "user", content: [ { type: "text", text: "hello" } ] } ],
      system: [ { type: "text", text: "system" } ],
      tools: [ { name: "tool_1", description: "Tool 1", input_schema: { type: "object", properties: {} } } ],
      cache_retention: "long"
    )

    assert_equal({ type: "ephemeral", ttl: "1h" }, body[:cache_control])
    assert_equal({ type: "ephemeral", ttl: "1h" }, body[:system][0][:cache_control])
    assert_equal({ type: "ephemeral", ttl: "1h" }, body[:tools][0][:cache_control])
    assert_nil body[:messages][0][:content][0][:cache_control]
  end

  test "does not mutate existing cache control when retention is none" do
    client = LlmGateway::Clients::Anthropic.new(model_key: "claude-3", api_key: "test")

    body = client.send(
      :build_body,
      [ { role: "user", content: [ { type: "text", text: "hello", cache_control: { type: "ephemeral" } } ] } ],
      system: [ { type: "text", text: "system", cache_control: { type: "ephemeral" } } ],
      tools: [ { name: "tool_1", description: "Tool 1", cache_control: { type: "ephemeral" }, input_schema: { type: "object", properties: {} } } ],
      cache_retention: "none"
    )

    assert_nil body[:cache_control]
    assert_equal({ type: "ephemeral" }, body[:system][0][:cache_control])
    assert_equal({ type: "ephemeral" }, body[:tools][0][:cache_control])
    assert_equal({ type: "ephemeral" }, body[:messages][0][:content][0][:cache_control])
  end
end
