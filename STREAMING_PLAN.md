# Streaming Support Plan — Anthropic First

Add streaming support using Ruby's `block_given?` idiom — if you call `chat` with a block, it streams; without a block, it behaves exactly as today. The streaming call **returns** the same normalized message hash as a non-streaming call, so the caller gets both real-time events and a clean transcript.

---

## API Usage

```ruby
# Non-streaming (unchanged)
result = LlmGateway::Client.chat("claude-3-7-sonnet-20250219", "Hello")

# Streaming — add a block, get events AND a return value
result = LlmGateway::Client.chat("claude-3-7-sonnet-20250219", "Hello") do |event|
  case event[:type]
  when :text_delta      # { type: :text_delta, text: "..." }
    print event[:text]
  when :thinking_delta  # { type: :thinking_delta, thinking: "..." }
    print event[:thinking]
  when :tool_use        # { type: :tool_use, id:, name:, input: {} }
    handle_tool(event)
  end
end

# result is the same shape as a non-streaming call:
# { id:, model:, usage:, choices: [{ role:, content: [...], finish_reason: }] }
# Identical to what OutputMapper.map returns — use for conversation history, logging, etc.
```

### Design Principles

- **Simple consumer API** — callers never deal with content block indexes, SSE framing, or accumulation. The 3 event types above are the entire streaming surface area.
- **Streaming returns a complete message** — the `StreamOutputMapper` accumulates all content blocks during the stream. When the stream ends, the accumulated response is run through the existing `OutputMapper` so the return value is identical to a non-streaming `chat` call. Usage, stop_reason, and full content are all in the return value — no need for `:usage` or `:done` events.
- **Text and thinking stream immediately** — these are the latency-sensitive events for display. Multiple text blocks from Claude (e.g., text → tool_use → text) appear as a continuous stream of `:text_delta` events with no gaps or index management.
- **Tool use is accumulated and emitted complete** — streamed partial JSON isn't useful to callers. The `StreamOutputMapper` collects `input_json_delta` chunks internally and emits one `:tool_use` event with fully parsed `input` when the content block finishes.
- **Errors mid-stream raise exceptions** — Claude can send `error` SSE events (e.g., `overloaded_error`). These are raised as `LlmGateway::Errors` exceptions, not surfaced as events.
- **Internal SSE events are hidden** — `message_start`, `content_block_start`, `content_block_stop`, `message_delta`, `message_stop`, `ping`, and `signature_delta` are all handled internally by the `StreamOutputMapper` and never yielded to callers.

---

## Anthropic SSE Events to Handle

| SSE Event | Surfaced? | What We Do |
|---|---|---|
| `message_start` | No | Capture `id`, `model`, `usage` into accumulator |
| `content_block_start` | No | Track new block in accumulator (text, tool_use, or thinking) |
| `content_block_delta` with `text_delta` | **Yes → `:text_delta`** | Append to accumulator, yield `{ type: :text_delta, text: }` |
| `content_block_delta` with `thinking_delta` | **Yes → `:thinking_delta`** | Append to accumulator, yield `{ type: :thinking_delta, thinking: }` |
| `content_block_delta` with `input_json_delta` | No | Append partial JSON to accumulator silently |
| `content_block_delta` with `signature_delta` | No | Store signature on accumulator block |
| `content_block_stop` | **Only for tool_use → `:tool_use`** | If block was `tool_use`, parse accumulated JSON, yield `{ type: :tool_use, id:, name:, input: }`. Otherwise no event. |
| `message_delta` | No | Capture `stop_reason`, merge cumulative `usage` into accumulator |
| `message_stop` | No | Stream finished — accumulator is complete |
| `ping` | No | Ignored |
| `error` | No (raises) | Raise `LlmGateway::Errors` exception |

---

## Layer-by-layer Changes (Anthropic only)

### 1. `BaseClient` — add `post_stream` method

New method alongside `post`:
- Builds the request the same way as `make_request` (URI, headers, JSON body)
- Uses `Net::HTTP#request` with a block to read the response body incrementally
- If status is not 200, collects the full body and calls `handle_error` as normal
- Parses raw SSE lines: splits on `\n\n` boundaries, extracts `event:` and `data:` fields
- Yields each parsed SSE event as `{ event: "message_start", data: { ... } }` to the given block

```
def post_stream(url_part, body = nil, extra_headers = {}, &block)
```

### 2. `Clients::Claude` — make `chat` block-aware

- Check `block_given?`
- **Without block**: unchanged — calls `post`, returns full response hash
- **With block**: adds `stream: true` to the body, calls `post_stream("messages", body) { |sse_event| yield sse_event }`, passing raw SSE events straight through
- Same change for `Clients::ClaudeCode` since it also hits the Anthropic API

### 3. `Adapter` — make `chat` block-aware

- Check `block_given?`
- **Without block**: exactly the same as today — input map → `client.chat` → output map → return hash
- **With block**:
  - Input mapping happens the same way (call `input_mapper.map` as normal)
  - Instantiate a `StreamOutputMapper` for the provider (new class, see below)
  - Call `client.chat(...) { |raw_sse| }` with a block
  - Inside the block, pass each raw SSE event through `stream_output_mapper.map_event(raw_sse)` which returns a normalized event (or nil for internal-only events)
  - Yield the normalized event to the caller's block when non-nil
  - After the stream ends, call `stream_output_mapper.to_message` to get the accumulated raw response, then run it through the existing `output_mapper.map` to produce the final normalized hash
  - **Return** the normalized hash — same shape as non-streaming `chat`

The adapter needs to know which stream output mapper to use:
- Add a `stream_output_mapper` keyword to `Adapter#initialize` (like `output_mapper`)
- Each provider adapter (e.g., `Claude::MessagesAdapter`) passes it in via `super`

### 4. New: `Adapters::Claude::StreamOutputMapper`

A new file: `lib/llm_gateway/adapters/claude/stream_output_mapper.rb`

Two responsibilities:
1. **`map_event(sse_event)`** — takes a raw SSE hash, updates accumulator, returns a normalized event or nil
2. **`to_message`** — returns the accumulated response in the same shape that Claude's non-streaming API returns (i.e., the shape that `OutputMapper.map` expects as input)

#### Accumulator State

```ruby
{
  id: "msg_...",
  model: "claude-...",
  stop_reason: "end_turn",
  usage: { input_tokens: 25, output_tokens: 50 },
  content: [
    { type: "thinking", thinking: "...", signature: "..." },
    { type: "text", text: "full accumulated text" },
    { type: "tool_use", id: "toolu_...", name: "get_weather", input: { location: "SF" } },
    { type: "text", text: "more text after tool use" }
  ]
}
```

This is exactly what Claude returns for a non-streaming request. The `to_message` method just returns this hash, which then gets passed to `OutputMapper.map` in the adapter to produce the normalized output.

#### Event Mapping

| Raw SSE event | Accumulator Update | Returns |
|---|---|---|
| `message_start` | Set `id`, `model`, `usage` | nil |
| `content_block_start` (text) | Push `{ type: "text", text: "" }` | nil |
| `content_block_start` (thinking) | Push `{ type: "thinking", thinking: "" }` | nil |
| `content_block_start` (tool_use) | Push `{ type: "tool_use", id:, name:, input_json: "" }` | nil |
| `content_block_delta` with `text_delta` | Append to current block's `text` | `{ type: :text_delta, text: }` |
| `content_block_delta` with `thinking_delta` | Append to current block's `thinking` | `{ type: :thinking_delta, thinking: }` |
| `content_block_delta` with `input_json_delta` | Append to current block's `input_json` | nil |
| `content_block_delta` with `signature_delta` | Set current block's `signature` | nil |
| `content_block_stop` (tool_use) | Parse `input_json` → `input`, delete `input_json` | `{ type: :tool_use, id:, name:, input: }` |
| `content_block_stop` (other) | — | nil |
| `message_delta` | Set `stop_reason`, merge `usage` | nil |
| `message_stop` | — | nil |
| `ping` | — | nil |
| `error` | — | Raise exception |

### 5. `Client` — pass the block through

- Add `&block` to `Client.chat` signature
- Pass it through: `adapter.chat(message, ..., &block)`
- The return value flows back naturally — `adapter.chat` returns the normalized hash whether streaming or not

### 6. Wiring — `llm_gateway.rb`

- Add `require_relative "llm_gateway/adapters/claude/stream_output_mapper"` to the requires list

### 7. `Claude::MessagesAdapter` — pass stream mapper to parent

Update constructor to pass the new stream output mapper:

```ruby
def initialize(client)
  super(
    client,
    input_mapper: InputMapper,
    output_mapper: OutputMapper,
    file_output_mapper: FileOutputMapper,
    stream_output_mapper: StreamOutputMapper
  )
end
```

---

## Files Changed

| File | Change |
|---|---|
| `lib/llm_gateway/base_client.rb` | Add `post_stream` method |
| `lib/llm_gateway/clients/claude.rb` | `chat` checks `block_given?`, adds `stream: true`, uses `post_stream` |
| `lib/llm_gateway/clients/claude_code.rb` | Same as above (if it has its own `chat`) |
| `lib/llm_gateway/adapters/adapter.rb` | `initialize` accepts `stream_output_mapper:`, `chat` checks `block_given?`, returns normalized hash from accumulated stream |
| `lib/llm_gateway/adapters/claude/stream_output_mapper.rb` | **New file** — `map_event` for real-time events, `to_message` for final accumulated response |
| `lib/llm_gateway/adapters/claude/messages_adapter.rb` | Pass `stream_output_mapper:` to super |
| `lib/llm_gateway/client.rb` | Add `&block` to `chat`, pass through |
| `lib/llm_gateway.rb` | Add require for stream_output_mapper |

## Files Unchanged

- `InputMapper` — input normalization is the same
- `OutputMapper` — still used for both streaming (on accumulated message) and non-streaming
- `BidirectionalMessageMapper` — unchanged, used by OutputMapper as before
- `ClientBuilder` — adapter construction unchanged
- All existing tests — no block = no streaming = same behavior
