# frozen_string_literal: true

require "test_helper"

class CloudflareAIGatewayStreamMapperTest < Test
  test "normalizes Anthropic Messages events and usage under the gateway identity" do
    response = map_chunks([
      { event: "message_start", data: { message: { id: "msg_cf", role: "assistant", model: "claude-haiku-5-5", usage: { input_tokens: 10 } } } },
      { event: "content_block_start", data: { index: 0, content_block: { type: "text", text: "" } } },
      { event: "content_block_delta", data: { index: 0, delta: { type: "text_delta", text: "blue" } } },
      { event: "content_block_stop", data: { index: 0 } },
      { event: "message_delta", data: { delta: { stop_reason: "end_turn" }, usage: { output_tokens: 2 } } },
      { event: "message_stop", data: {} }
    ])
    assert_equal "blue", response.content.first.text
    assert_equal "stop", response.stop_reason
    assert_equal 10, response.usage[:input]
    assert_equal 2, response.usage[:output]
  end

  test "normalizes native Chat Completions frames as well as Messages" do
    response = map_chunks([
      { data: { id: "chat_cf", model: "upstream", choices: [ { delta: { role: "assistant", content: "blue" } } ] } },
      { data: { choices: [ { delta: {}, finish_reason: "stop" } ] } },
      { data: { choices: [], usage: { prompt_tokens: 10, completion_tokens: 2 } } }
    ])
    assert_equal "blue", response.content.first.text
    assert_equal "stop", response.stop_reason
    assert_equal 10, response.usage[:input]
    assert_equal 2, response.usage[:output]
  end

  test "preserves upstream stream errors" do
    mapper = new_mapper
    assert_raises(LlmGateway::Errors::OverloadError) do
      mapper.map(event: "error", data: { error: { type: "overloaded_error", message: "Busy" } })
    end
  end

  test "rejects unknown stream formats and empty streams" do
    mapper = new_mapper
    assert_raises(LlmGateway::Errors::APIStatusError) { mapper.map(data: { candidates: [] }) }
    assert_raises(LlmGateway::Errors::APIStatusError) { new_mapper.finish }
  end

  test "ignores leading keepalives before detecting the response protocol" do
    mapper = new_mapper
    mapper.map(event: "ping", data: { type: "ping" })
    mapper.map(event: "message_start", data: { message: { id: "msg_cf", role: "assistant", model: "claude" } })
    mapper.map(event: "message_delta", data: { delta: { stop_reason: "end_turn" } })
    mapper.map(event: "message_stop", data: {})
    mapper.finish
    assert_equal "stop", mapper.result.stop_reason
  end

  private

  def new_mapper
    LlmGateway::Adapters::CloudflareAIGateway::StreamMapper.new(provider: "cloudflare-ai-gateway", api: "messages")
  end

  def map_chunks(chunks)
    mapper = new_mapper
    chunks.each { |chunk| mapper.map(chunk) }
    mapper.finish
    mapper.result.tap do |response|
      assert_equal "cloudflare-ai-gateway", response.provider
      assert_equal "messages", response.api
    end
  end
end
