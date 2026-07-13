# Migration guide: v0.8.1 to v0.9.0

This guide covers user-facing changes since the latest released gem, `v0.8.1`.

Relevant PRs/changes:

- #95: pass the persisted session event into tool execution
- #97: fix harness queue draining semantics
- current branch: tools return `LlmGateway::Agents::Event::ToolCallResult` objects instead of hashes/strings, with `is_error` support

## 1. Update custom tools to accept `tool_use_id:` and return `ToolCallResult`

Custom `LlmGateway::Tool` subclasses must now return a `LlmGateway::Agents::Event::ToolCallResult` object, or a subclass of it. Use the inherited `tool_result` helper for the common case.

### Before

```ruby
class AddTool < LlmGateway::Tool
  name "add"
  description "Add two numbers"
  input_schema(type: "object")

  def execute(input)
    input[:left] + input[:right]
  end
end
```

### After

```ruby
class AddTool < LlmGateway::Tool
  name "add"
  description "Add two numbers"
  input_schema(type: "object")

  def execute(input, tool_use_id:)
    tool_result(input[:left] + input[:right], tool_use_id: tool_use_id)
  end
end
```

If a tool returns anything other than `ToolCallResult`, the prompt/harness catches the resulting `TypeError` and sends an error result to the model instead. The exception does not escape from the normal tool loop.

## 2. Use `is_error:` for failed tool results when needed

`ToolCallResult` now includes an `is_error` boolean and serializes it through `to_h`.

```ruby
LlmGateway::Agents::Event::ToolCallResult.new(
  tool_use_id: tool_use_id,
  content: "Something went wrong",
  is_error: true
)
```

The default is `false`.

## 3. Update event consumers for tool result objects

Harness events now expose tool results as `ToolCallResult` objects, not raw hashes or provider-specific `ToolResult` structs.

Affected events:

- `:tool_execution_end` via `event.result`
- `:turn_end` via `event.tool_results`

### Before

```ruby
case event.type
when :tool_execution_end
  puts event.result[:content]
when :turn_end
  event.tool_results.each { |result| persist(result) }
end
```

### After

```ruby
case event.type
when :tool_execution_end
  puts event.result.content
when :turn_end
  event.tool_results.each { |result| persist(result.to_h) }
end
```

## 4. Wrap tool execution if needed

`Prompt` and `Harness` now call the protected `execute_tool_requests` hook to execute a batch of tool requests. If you already override tool execution, migrate that customization to this hook. Override it on a `Prompt` or `Harness` subclass when you need setup before tools run, post-processing after results return, or customization of the transcript message that carries tool results. Call `yield requests` to let llm_gateway execute tools normally, then return a `LlmGateway::Agents::Event::ToolResultMessage`.

```ruby
class MyHarness < LlmGateway::Agents::Harness
  def execute_tool_requests(requests:, assistant_message:, session_event:)
    context = build_context(requests, assistant_message)
    results = yield requests
    audit_results(context, results)

    LlmGateway::Agents::Event::ToolResultMessage.new(
      content: results,
      details: { assistant_message_id: assistant_message.id }
    )
  end
end
```

The default `ToolResultMessage` serializes as:

```ruby
{
  role: "user",
  content: tool_results.map(&:to_h)
}
```

## 5. Review harness queue behavior

Harness queue semantics changed to avoid stale queues and recursive runs.

- `default_queue_mode` is now `:follow_up` instead of `:next_turn`.
- `next_turn_message` was removed.
- Valid `default_queue_mode` values are now `:steer` and `:follow_up`.
- `prompt_message`, `steer_message`, and `follow_up_message` always enqueue first.
- If the agent is idle, those methods enqueue and then call `continue`.
- `continue` now raises `RuntimeError, "Cannot continue a busy agent"` if called while the session is busy.
- `continue` marks the session busy, drains `:steer`, drains `:follow_up`, runs, and marks the session idle.

### Before

```ruby
harness.default_queue_mode = :next_turn
harness.next_turn_message("do this after the current run")
```

### After

```ruby
harness.default_queue_mode = :follow_up
harness.follow_up_message("do this after the current turn")
```

If you previously relied on `next_turn` work running after the entire agent run, move that behavior into your application-level scheduler or enqueue a `follow_up` after the current operation completes.

## 6. Tool execution can access the persisted session event

For a `Harness`, `execute_tool_requests` receives the persisted assistant session event as `session_event:`. This is useful for subclasses/custom harnesses that need access to the stored message/event that produced the tool call. `Prompt` invokes the same hook with `session_event: nil`, because it has no session manager.

Existing simple tools do not receive this event directly and do not need to use it; they only need the `execute(input, tool_use_id:)` signature and `ToolCallResult` return value described above.

## 7. Message metadata is safe to keep in transcripts

Input messages may now carry app-owned metadata, such as a `details` hash. The gateway preserves it locally but strips unsupported metadata before sending user/assistant messages to providers.

```ruby
adapter.stream([
  {
    role: "user",
    content: "Hello",
    details: { trace_id: "msg-123" }
  }
])
```

No migration is required unless you previously stripped this metadata yourself; that cleanup can now be simplified.
