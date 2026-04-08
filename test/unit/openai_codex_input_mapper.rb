# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../lib/llm_gateway/adapters/openai_codex/input_mapper"

MAPPER = LlmGateway::Adapters::OpenAICodex::InputMapper

class OpenAICodexInputMapperTest < Test
  # ---------------------------------------------------------------------------
  # map / map_messages — happy-path pass-through
  # ---------------------------------------------------------------------------

  test "passes through simple user text message" do
    messages = [ { role: "user", content: "Hello" } ]
    result   = MAPPER.map_messages(messages)

    assert_equal 1, result.length
    assert_equal "user", result[0][:role]
    assert_equal [ { type: "input_text", text: "Hello" } ], result[0][:content]
  end

  test "returns messages unchanged when not an array" do
    assert_equal "raw", MAPPER.map_messages("raw")
  end

  test "maps tools via inherited map_tools (input_schema → parameters)" do
    mapped = MAPPER.map(
      messages: [ { role: "user", content: "Hi" } ],
      response_format: { type: "text" },
      tools: [
        {
          name: "add",
          description: "Add two numbers",
          input_schema: { type: "object", properties: { a: { type: "number" } } }
        }
      ],
      system: []
    )

    assert_equal 1, mapped[:tools].length
    tool = mapped[:tools].first
    assert_equal "function", tool[:type]
    assert_equal "add",      tool[:name]
    assert tool[:parameters]
  end

  # ---------------------------------------------------------------------------
  # strip_reasoning_blocks
  # ---------------------------------------------------------------------------

  test "strips 'reasoning' type blocks from messages" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "reasoning", id: "rs_1", summary: [] },
          { type: "text",      text: "Here is my answer." }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    content_types = result.flat_map { |m| Array(m[:content]).map { |p| p[:type] } }
    assert_includes content_types, "output_text"
    refute_includes content_types, "reasoning"
  end

  test "strips 'summary_text' type blocks" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "summary_text", text: "Summary here" },
          { type: "text",         text: "Answer" }
        ]
      }
    ]
    result         = MAPPER.map_messages(messages)
    content_types  = result.flat_map { |m| Array(m[:content]).map { |p| p[:type] } }
    refute_includes content_types, "summary_text"
    assert_includes content_types, "output_text"
  end

  test "strips unsigned 'thinking' blocks (no signature)" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "thinking", thinking: "internal monologue" },
          { type: "text",     text: "Done." }
        ]
      }
    ]
    result         = MAPPER.map_messages(messages)
    content_types  = result.flat_map { |m| Array(m[:content]).map { |p| p[:type] } }
    refute_includes content_types, "thinking"
  end

  test "keeps 'thinking' blocks that carry a signature" do
    signature_payload = JSON.generate({ type: "thinking", id: "think_1", thinking: "enc" })
    messages = [
      {
        role: "assistant",
        content: [
          { type: "thinking", thinking: "enc", signature: signature_payload },
          { type: "text",     text: "Done." }
        ]
      }
    ]
    # The signature JSON is parsed and inserted as a top-level item, so the
    # result should contain a thinking/reasoning item alongside the text block.
    result = MAPPER.map_messages(messages)
    types  = result.map { |item| item[:type]&.to_s || item[:role]&.to_s }
    assert_includes types, "thinking"
  end

  # ---------------------------------------------------------------------------
  # normalize_assistant_content_types
  # ---------------------------------------------------------------------------

  test "converts input_text to output_text on assistant messages" do
    # Force a scenario where the mapper would produce input_text for assistant
    # by building a result that still has input_text and running normalize.
    messages = [ { role: "assistant", content: [ { type: "input_text", text: "Hi" } ] } ]
    normalized = MAPPER.send(:normalize_assistant_content_types, messages)

    assert_equal "output_text", normalized.first[:content].first[:type]
  end

  test "leaves non-assistant messages untouched by normalize" do
    messages = [ { role: "user", content: [ { type: "input_text", text: "Hi" } ] } ]
    normalized = MAPPER.send(:normalize_assistant_content_types, messages)

    assert_equal "input_text", normalized.first[:content].first[:type]
  end

  # ---------------------------------------------------------------------------
  # Assistant content → top-level function_call items
  # ---------------------------------------------------------------------------

  test "promotes tool_use blocks in assistant content to top-level function_call items" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "tool_use", id: "call_abc", name: "search", input: { q: "ruby" } }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    fc = result.find { |item| item[:type] == "function_call" }
    assert fc,                             "Expected a function_call item"
    assert_equal "search",    fc[:name]
    assert_equal "call_abc",  fc[:call_id]
    assert_equal '{"q":"ruby"}', fc[:arguments]
  end

  test "promotes function_call blocks in assistant content to top-level items" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "function_call", call_id: "cid_1", name: "fn", arguments: '{"x":1}' }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    fc = result.find { |item| item[:type] == "function_call" }
    assert fc
    assert_equal "fn",      fc[:name]
    assert_equal "cid_1",   fc[:call_id]
    assert_equal '{"x":1}', fc[:arguments]
  end

  test "serialises hash arguments to JSON for function_call items" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "tool_use", id: "c1", name: "calc", input: { a: 1, b: 2 } }
        ]
      }
    ]
    result    = MAPPER.map_messages(messages)
    fc        = result.find { |item| item[:type] == "function_call" }
    parsed    = JSON.parse(fc[:arguments])

    assert_equal({ "a" => 1, "b" => 2 }, parsed)
  end

  test "mixed assistant turn: text first, then function_call items" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "text",     text: "Sure, let me look that up." },
          { type: "tool_use", id: "c2", name: "lookup", input: {} }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    text_msg = result.find { |item| item[:role] == "assistant" }
    fc       = result.find { |item| item[:type] == "function_call" }

    assert text_msg, "Expected assistant text message"
    assert_equal [ { type: "output_text", text: "Sure, let me look that up." } ], text_msg[:content]
    assert fc
    assert_equal "lookup", fc[:name]
  end

  # ---------------------------------------------------------------------------
  # Tool-result messages
  # ---------------------------------------------------------------------------

  test "expands tool_result user messages to top-level function_call_output items" do
    messages = [
      {
        role: "user",
        content: [
          {
            type: "tool_result",
            tool_use_id: "call_abc",
            content: [ { type: "text", text: "42" } ]
          }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    assert_equal 1, result.length
    item = result.first
    assert_equal "function_call_output", item[:type]
    assert_equal "call_abc",             item[:call_id]
  end

  test "expands tool_result developer-role messages to top-level function_call_output items" do
    messages = [
      {
        role: "developer",
        content: [
          {
            type: "tool_result",
            tool_use_id: "call_xyz",
            content: "42"
          }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    assert_equal 1, result.length
    item = result.first
    assert_equal "function_call_output", item[:type]
    assert_equal "call_xyz",             item[:call_id]
  end

  test "normalises string tool result output to input_text" do
    output   = MAPPER.send(:normalize_tool_result_output, [ "some text" ])
    assert_equal [ { type: "input_text", text: "some text" } ], output
  end

  test "normalises text-hash tool result output to input_text" do
    output = MAPPER.send(:normalize_tool_result_output, [ { type: "text", text: "hello" } ])
    assert_equal [ { type: "input_text", text: "hello" } ], output
  end

  test "normalises output_text hash to input_text" do
    output = MAPPER.send(:normalize_tool_result_output, [ { type: "output_text", text: "world" } ])
    assert_equal [ { type: "input_text", text: "world" } ], output
  end

  test "normalises image hash to input_image with data URI" do
    output = MAPPER.send(:normalize_tool_result_output, [
      { type: "image", data: "abc123", media_type: "image/png" }
    ])
    assert_equal 1,             output.length
    assert_equal "input_image", output.first[:type]
    assert_includes output.first[:image_url], "data:image/png;base64,abc123"
  end

  test "normalises image hash to input_image when image_url already present" do
    output = MAPPER.send(:normalize_tool_result_output, [
      { type: "input_image", image_url: "https://example.com/img.png" }
    ])
    assert_equal "input_image",                    output.first[:type]
    assert_equal "https://example.com/img.png",    output.first[:image_url]
  end

  test "converts non-hash, non-string output items to input_text" do
    output = MAPPER.send(:normalize_tool_result_output, [ 42 ])
    assert_equal [ { type: "input_text", text: "42" } ], output
  end

  # ---------------------------------------------------------------------------
  # Thinking with signature → parsed reasoning item
  # ---------------------------------------------------------------------------

  test "inserts parsed signature JSON as reasoning item for signed thinking blocks" do
    reasoning_item    = { type: "reasoning", id: "rs_xyz", encrypted_content: "enc==" }
    signature_payload = JSON.generate(reasoning_item)

    messages = [
      {
        role: "assistant",
        content: [
          { type: "thinking", thinking: "...", signature: signature_payload },
          { type: "text",     text: "My answer." }
        ]
      }
    ]
    result = MAPPER.map_messages(messages)

    rs = result.find { |item| item[:type]&.to_s == "reasoning" }
    assert rs,                      "Expected a reasoning item from signature"
    assert_equal "rs_xyz", rs[:id]
  end

  test "silently drops thinking blocks with malformed JSON signature" do
    messages = [
      {
        role: "assistant",
        content: [
          { type: "thinking", thinking: "...", signature: "not json{{{" },
          { type: "text",     text: "Fallback." }
        ]
      }
    ]
    # Should not raise; the malformed signature is dropped.
    result = assert_silent { MAPPER.map_messages(messages) }
    assert result
  end

  # ---------------------------------------------------------------------------
  # Full multi-turn conversation
  # ---------------------------------------------------------------------------

  test "full multi-turn: user → assistant (text+tool_use) → user (tool_result) → assistant (text)" do
    messages = [
      { role: "user",      content: "What is 2+2?" },
      {
        role: "assistant",
        content: [
          { type: "text",     text: "Let me calculate." },
          { type: "tool_use", id: "c99", name: "calc", input: { a: 2, b: 2, op: "add" } }
        ]
      },
      {
        role: "user",
        content: [
          { type: "tool_result", tool_use_id: "c99", content: [ { type: "text", text: "4" } ] }
        ]
      },
      { role: "assistant", content: [ { type: "text", text: "The answer is 4." } ] }
    ]

    result = MAPPER.map_messages(messages)

    roles_and_types = result.map { |item| item[:role] || item[:type] }

    # User turn
    assert_includes roles_and_types, "user"
    # Assistant text
    assistant_items = result.select { |i| i[:role] == "assistant" }
    assert(assistant_items.any? { |i| i[:content]&.any? { |p| p[:text]&.include?("calculate") } })
    # function_call top-level item
    assert_includes roles_and_types, "function_call"
    # function_call_output top-level item
    assert_includes roles_and_types, "function_call_output"
    # Final assistant text
    assert(assistant_items.any? { |i| i[:content]&.any? { |p| p[:text]&.include?("4") } })
  end
end
