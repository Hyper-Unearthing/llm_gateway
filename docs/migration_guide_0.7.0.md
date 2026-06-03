# Migration guide: 0.7.0

This release refactors `LlmGateway::Prompt` around the normalized streaming response model and adds first-class prompt-owned tool loops.

## Breaking changes

### `Prompt.new` uses keyword arguments

Prompt instance configuration is now keyword-only:

```ruby
# Before
SummaryPrompt.new(provider, "claude-sonnet-4-20250514").run

# After
SummaryPrompt.new(
  provider: provider,
  model: "claude-sonnet-4-20250514"
).run
```

The same applies when overriding class defaults for `reasoning`, `cache_key`, or `cache_retention`.

Class-level prompt defaults should be assigned with writer methods:

```ruby
class SummaryPrompt < LlmGateway::Prompt
  self.provider = provider
  self.model = "gpt-5.4"
  self.reasoning = "medium"
end
```

If you used the older setter-style calls (`provider value` or `model value`) in prompt subclasses, switch to `self.provider = value` / `self.model = value`.

### `Prompt#run` uses `stream` and normalized `AssistantMessage`

`run` now calls the configured provider's `stream` method and expects it to return a normalized `LlmGateway::AssistantMessage` with `content` blocks.

If you use test doubles or custom providers with `Prompt`, update them from hash-like chat responses:

```ruby
# Before
{ choices: [ { content: "hello" } ] }
```

To `AssistantMessage` responses:

```ruby
LlmGateway::AssistantMessage.new(
  id: "msg_123",
  model: "gpt-5.4",
  role: "assistant",
  stop_reason: "stop",
  provider: "openai",
  api: "responses",
  timestamp: Time.now.to_i,
  usage: {},
  content: [ { type: "text", text: "hello" } ]
)
```

`run` returns the final normalized `AssistantMessage` after tool handling is complete. It no longer extracts or concatenates text content for you; inspect `response.content` when you need text or other blocks.

`after_execute` callbacks now receive only the final `AssistantMessage` instead of both the message and extracted text.

Prompt callback storage now uses Rails-style `class_attribute` inheritance. Register callbacks with `before_execute` / `after_execute` or assign a duplicated callback array on the subclass; avoid mutating inherited callback arrays directly with `before_execute_callbacks << ...` because that can affect related classes.

### `extract_response` and `parse_response` hooks were removed

`Prompt#run` no longer calls custom `extract_response` or `parse_response` methods.

Move response transformation outside the prompt call, or wrap `run` in your subclass:

```ruby
class JsonPrompt < LlmGateway::Prompt
  def prompt
    "Return JSON."
  end

  def run_json(**options)
    response = run(**options)
    text = response.content.select { |block| block.type == "text" }.map(&:text).join
    JSON.parse(text)
  end
end
```

### Tools are declared with `TOOLS`

Prompt tools are now class-level tool classes declared in a `TOOLS` constant. `Prompt#tools` returns their provider definitions.

```ruby
class AddTool < LlmGateway::Tool
  name "add"
  description "Adds two numbers"
  input_schema(type: "object")
  cache true # optional cache_control marker where supported

  def execute(input)
    input[:left] + input[:right]
  end
end

class MathPrompt < LlmGateway::Prompt
  TOOLS = [AddTool].freeze

  def prompt
    "What is 2 + 3? Use the add tool."
  end
end
```

If a prompt has no tools, `tools` now returns `[]` instead of `nil`.

### `run` automatically loops over tool calls

When the assistant returns `tool_use` content blocks, `Prompt#run` now:

1. Finds the matching class in `TOOLS` by tool name.
2. Executes `tool_class.new.execute(input)`.
3. Appends the assistant message and a user `tool_result` message.
4. Calls `stream` again.
5. Repeats until the response has no `tool_use` blocks.

Unknown tools and tool execution errors are returned to the model as `tool_result` content rather than raised.

### Prompt input is resolved once per run

`prompt` is evaluated once at the start of `run`. The same initial input is used when building follow-up messages for tool results, so dynamic or expensive prompt builders are not re-evaluated during a single run.

### `Prompt#stream` accepts explicit input and forwards reasoning/cache options

`stream` now has this signature:

```ruby
stream(input = prompt, provider: nil, model: nil, reasoning: nil, **options, &block)
```

You can still call `stream` with no input, but subclasses or callers can now provide a transcript directly:

```ruby
prompt.stream([{ role: "user", content: "Hello" }], model: "gpt-5.4")
```

`Prompt` also now forwards `reasoning:` when configured on the class, instance, `run`, or `stream` call.

### Prompt-level cache options

Prompt instances accept and forward cache options:

```ruby
SummaryPrompt.new(
  provider: provider,
  model: "gpt-5.4",
  cache_key: "summary-v1",
  cache_retention: "short"
).run
```

These are passed to providers as managed `cache_key` / `cache_retention` stream options. For providers that support cache control on system/tool blocks, `cache_retention` may also apply cache metadata to the prompt-owned `system_prompt` and tool definitions. Tool classes can also opt into cache metadata with `cache true`.

### Stream callbacks may see server-tool events and content blocks

Provider-hosted tools (for example OpenAI code interpreter or Anthropic code execution) are normalized as distinct server-tool blocks:

- `server_tool_use`
- `server_tool_result`
- provider-specific `*_tool_result` blocks during streaming/finalization

Stream callbacks may now receive additional event types when server tools are used:

- `:tool_result_start`
- `:tool_result_delta`
- `:tool_result_end`

`tool_start` events also expose `event.tool_type`, which is either `"tool_use"` or `"server_tool_use"`.

If your stream handler exhaustively switches on event/content types, add fallbacks or handlers for these server-tool cases. Cross-provider handoff sanitization may convert server-tool blocks to regular `tool_use` / `tool_result` blocks when replaying transcripts on a different provider/API.

## Migration checklist

- [ ] Replace positional `Prompt.new(provider, model)` calls with `Prompt.new(provider: provider, model: model)`.
- [ ] Replace prompt class setter-style calls (`provider value`, `model value`) with `self.provider = value` / `self.model = value`.
- [ ] Update custom provider/test doubles used by `Prompt` to return `AssistantMessage`.
- [ ] Remove `extract_response` and `parse_response` hooks; inspect, parse, or transform the returned `AssistantMessage` after `run`.
- [ ] Update `after_execute` callbacks to accept the final `AssistantMessage` only.
- [ ] Replace direct mutations of `before_execute_callbacks` / `after_execute_callbacks` with the callback registration methods or explicit subclass assignments.
- [ ] Move prompt tool definitions to a `TOOLS = [ToolClass]` constant.
- [ ] Account for automatic tool-loop execution in `run`.
- [ ] Update any `tools.nil?` checks; no-tool prompts now expose `[]`.
- [ ] Use `cache_key:` / `cache_retention:` on prompt instances when prompt caching is needed.
- [ ] Add stream/content handling for server-tool event types if your callback code is exhaustive.
