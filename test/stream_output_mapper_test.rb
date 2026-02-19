# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/llm_gateway"

class StreamOutputMapperTest < Minitest::Test
  def setup
    @mapper = LlmGateway::Adapters::Claude::StreamOutputMapper.new
  end

  def test_message_start_returns_nil_and_captures_metadata
    event = {
      event: "message_start",
      data: {
        message: {
          id: "msg_123",
          model: "claude-3-7-sonnet-20250219",
          usage: { input_tokens: 25, output_tokens: 0 }
        }
      }
    }

    result = @mapper.map_event(event)
    assert_nil result

    msg = @mapper.to_message
    assert_equal "msg_123", msg[:id]
    assert_equal "claude-3-7-sonnet-20250219", msg[:model]
    assert_equal({ input_tokens: 25, output_tokens: 0 }, msg[:usage])
  end

  def test_text_delta_yields_event_and_accumulates
    # Start message
    @mapper.map_event({ event: "message_start", data: { message: { id: "msg_1", model: "claude", usage: {} } } })

    # Start text block
    @mapper.map_event({ event: "content_block_start", data: { index: 0, content_block: { type: "text", text: "" } } })

    # Text deltas
    r1 = @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "text_delta", text: "Hello" } } })
    r2 = @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "text_delta", text: " world" } } })

    assert_equal({ type: :text_delta, text: "Hello" }, r1)
    assert_equal({ type: :text_delta, text: " world" }, r2)

    # Stop block
    @mapper.map_event({ event: "content_block_stop", data: { index: 0 } })
    @mapper.map_event({ event: "message_delta", data: { delta: { stop_reason: "end_turn" }, usage: { output_tokens: 10 } } })
    @mapper.map_event({ event: "message_stop", data: {} })

    msg = @mapper.to_message
    assert_equal "end_turn", msg[:stop_reason]
    assert_equal [{ type: "text", text: "Hello world" }], msg[:content]
  end

  def test_thinking_delta_yields_event
    @mapper.map_event({ event: "message_start", data: { message: { id: "msg_1", model: "claude", usage: {} } } })
    @mapper.map_event({ event: "content_block_start", data: { index: 0, content_block: { type: "thinking", thinking: "" } } })

    r = @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "thinking_delta", thinking: "Let me think..." } } })

    assert_equal({ type: :thinking_delta, thinking: "Let me think..." }, r)

    # Signature
    r2 = @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "signature_delta", signature: "sig123" } } })
    assert_nil r2

    @mapper.map_event({ event: "content_block_stop", data: { index: 0 } })

    msg = @mapper.to_message
    assert_equal "thinking", msg[:content][0][:type]
    assert_equal "Let me think...", msg[:content][0][:thinking]
    assert_equal "sig123", msg[:content][0][:signature]
  end

  def test_tool_use_accumulated_and_emitted_on_stop
    @mapper.map_event({ event: "message_start", data: { message: { id: "msg_1", model: "claude", usage: {} } } })
    @mapper.map_event({ event: "content_block_start", data: { index: 0, content_block: { type: "tool_use", id: "toolu_1", name: "get_weather" } } })

    # Partial JSON deltas should return nil
    r1 = @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "input_json_delta", partial_json: '{"loc' } } })
    r2 = @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "input_json_delta", partial_json: 'ation": "SF"}' } } })

    assert_nil r1
    assert_nil r2

    # On stop, emits the complete tool_use event
    r3 = @mapper.map_event({ event: "content_block_stop", data: { index: 0 } })

    assert_equal :tool_use, r3[:type]
    assert_equal "toolu_1", r3[:id]
    assert_equal "get_weather", r3[:name]
    assert_equal({ location: "SF" }, r3[:input])
  end

  def test_error_event_raises_exception
    assert_raises(LlmGateway::Errors::OverloadError) do
      @mapper.map_event({ event: "error", data: { error: { type: "overloaded_error", message: "Overloaded" } } })
    end
  end

  def test_ping_returns_nil
    result = @mapper.map_event({ event: "ping", data: {} })
    assert_nil result
  end

  def test_full_stream_produces_output_mapper_compatible_message
    # Simulate a full stream
    @mapper.map_event({ event: "message_start", data: { message: { id: "msg_abc", model: "claude-3-7-sonnet-20250219", usage: { input_tokens: 10, output_tokens: 0 } } } })
    @mapper.map_event({ event: "content_block_start", data: { index: 0, content_block: { type: "text", text: "" } } })
    @mapper.map_event({ event: "content_block_delta", data: { index: 0, delta: { type: "text_delta", text: "Hi there!" } } })
    @mapper.map_event({ event: "content_block_stop", data: { index: 0 } })
    @mapper.map_event({ event: "message_delta", data: { delta: { stop_reason: "end_turn" }, usage: { output_tokens: 5 } } })
    @mapper.map_event({ event: "message_stop", data: {} })

    raw = @mapper.to_message

    # Now pass through OutputMapper — should produce the same shape as non-streaming
    result = LlmGateway::Adapters::Claude::OutputMapper.map(raw)

    assert_equal "msg_abc", result[:id]
    assert_equal "claude-3-7-sonnet-20250219", result[:model]
    assert_equal "end_turn", result[:choices][0][:finish_reason]
    assert_equal "assistant", result[:choices][0][:role]
    assert_equal "text", result[:choices][0][:content][0][:type]
    assert_equal "Hi there!", result[:choices][0][:content][0][:text]
  end
end
