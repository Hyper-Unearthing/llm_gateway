# Migration Guide: 0.5.0 to 0.6.0

This guide covers user-facing changes between `v0.5.0` and the latest commit on the 0.6.0 branch.

## Summary

0.6.0 separates provider authentication/configuration from model selection.

- Provider config now contains only provider/auth settings such as `provider`, `api_key`, `access_token`, and `account_id`.
- `model_key` is no longer accepted in provider/client configuration.
- Pass the model per request with `model:` when calling `chat`, `stream`, Responses/Codex methods, or embeddings.
- Legacy provider keys such as `openai_apikey_responses` were removed. Use the shorter provider keys.
- `LlmGateway::Prompt` now accepts/configures a provider and model separately, and uses `stream` internally.
- The `client.model_key` reader was removed; track the selected model at the call site or read it from returned messages.
- Streaming events now expose accumulated partial messages during the stream, while `:message_end` exposes the final message through `event.message`.
- Non-final stream event hashes now include `partial`; normal stream consumers are unaffected, but strict `event.to_h` snapshots/comparisons may need updates.
- Normalized usage counters were renamed to concise keys: `:input`, `:cache_write`, `:cache_read`, and `:output`; `:reasoning_tokens` was removed.
- Streamed assistant messages now include `timestamp` as Unix milliseconds.
- Custom stream mappers must initialize with provider/API metadata and emit a final `:message_end` patch.

## 1. Replace legacy provider keys

0.6.0 removes the backward-compatible legacy provider registry entries.

| 0.5.0 provider key | 0.6.0 provider key |
|---|---|
| `anthropic_apikey_messages` | `anthropic_messages` |
| `anthropic_oauth_messages` | `anthropic_messages` |
| `openai_apikey_completions` | `openai_completions` |
| `openai_apikey_responses` | `openai_responses` |
| `openai_oauth_codex` | `openai_codex` |
| `groq_apikey_completions` | `groq_completions` |

### Before

```ruby
adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)
```

### After

```ruby
adapter = LlmGateway.build_provider(
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
)
```

## 2. Move `model_key` from provider config to request calls

`model_key` is no longer a provider option. Passing it to `LlmGateway.build_provider` raises:

```text
ArgumentError: model_key is no longer a provider option; pass model: to chat/stream instead
```

Pass `model:` on each request instead.

### Streaming

```ruby
# Before
adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)
result = adapter.stream("Write one short sentence about Ruby.")

# After
adapter = LlmGateway.build_provider(
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
)
result = adapter.stream("Write one short sentence about Ruby.", model: "gpt-5.4")
```

### Configure arrays

```ruby
# Before
LlmGateway.configure([
  {
    name: "primary",
    config: {
      provider: "groq_apikey_completions",
      api_key: ENV.fetch("GROQ_API_KEY"),
      model_key: "openai/gpt-oss-120b"
    }
  }
])

# After
LlmGateway.configure([
  {
    name: "primary",
    config: {
      provider: "groq_completions",
      api_key: ENV.fetch("GROQ_API_KEY")
    }
  }
])

LlmGateway.configured_clients.fetch("primary").stream(
  "Hello",
  model: "openai/gpt-oss-120b"
)
```

## 3. Update direct client usage

Direct clients no longer take `model_key:` in their constructors.

```ruby
# Before
client = LlmGateway::Clients::OpenAI.new(
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)
client.stream(messages)

# After
client = LlmGateway::Clients::OpenAI.new(
  api_key: ENV.fetch("OPENAI_API_KEY")
)
client.stream(messages, model: "gpt-5.4")
```

The same pattern applies to:

- `LlmGateway::Clients::Anthropic#chat` / `#stream`
- `LlmGateway::Clients::OpenAI#chat` / `#stream` / `#responses` / `#stream_responses`
- `LlmGateway::Clients::OpenAI#chat_codex` / `#stream_codex`
- `LlmGateway::Clients::Groq#chat` / `#stream`

Embeddings also take a per-call model:

```ruby
client.generate_embeddings(input, model: "text-embedding-3-large")
```

If omitted, clients still provide default models.

## 4. Update `LlmGateway::Prompt` classes

`Prompt` no longer looks up a configured client by comparing a string to `client.model_key`. It now keeps the provider and model as separate values.

If you previously called `Prompt.new("gpt-5.4")`, update that code. The first initializer argument is now a provider adapter, not a model lookup key. Configure a provider on the class or pass one to the initializer.

### Class-level configuration

```ruby
class SummaryPrompt < LlmGateway::Prompt
  self.provider = LlmGateway.build_provider(
    provider: "openai_responses",
    api_key: ENV.fetch("OPENAI_API_KEY")
  )
  self.model = "gpt-5.4"

  def prompt
    "Summarize this text."
  end
end

SummaryPrompt.new.run
```


### Instance-level configuration

```ruby
provider = LlmGateway.build_provider(
  provider: "anthropic_messages",
  api_key: ENV.fetch("ANTHROPIC_API_KEY")
)

SummaryPrompt.new(provider, "claude-sonnet-4-20250514").run
```

### Per-call overrides

```ruby
prompt = SummaryPrompt.new(default_provider, "gpt-5.1")

prompt.stream(
  provider: other_provider,
  model: "gpt-5.4",
  reasoning: "high"
)
```

If you subclassed `Prompt` and called or overrode `post`, migrate that code to `stream`. `run` now calls `stream` internally.

## 5. Stop using `client.model_key`

Direct clients no longer expose a `model_key` reader because model selection is no longer client/provider state.

```ruby
# Before
client = LlmGateway::Clients::OpenAI.new(
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)
puts client.model_key

# After
client = LlmGateway::Clients::OpenAI.new(
  api_key: ENV.fetch("OPENAI_API_KEY")
)
model = "gpt-5.4"
result = client.stream(messages, model: model)
# Track `model` at the call site when you need it later.
```

## 6. OAuth provider names

OAuth is now represented by credentials, not by separate legacy provider keys.

```ruby
# Before
adapter = LlmGateway.build_provider(
  provider: "openai_oauth_codex",
  access_token: current_access_token,
  model_key: "gpt-5.4"
)

# After
adapter = LlmGateway.build_provider(
  provider: "openai_codex",
  access_token: current_access_token
)

adapter.stream("Hello from OAuth auth", model: "gpt-5.4")
```

For Anthropic OAuth, use `provider: "anthropic_messages"` with an `access_token`.

## 7. Update stream callback handling

The final `:message_end` stream callback event changed shape.

In 0.5.x, `:message_end` was an `AssistantStreamMessageEvent` and exposed the accumulated message through `event.partial`.

In 0.6.0, `:message_end` is an `AssistantStreamMessageEndEvent` and exposes the final complete `AssistantMessage` through `event.message`. It does not expose `partial`.

```ruby
response = adapter.stream("Hello", model: "gpt-5.4") do |event|
  case event.type
  when :text_delta
    print event.delta
  when :message_end
    final_message = event.message
    puts final_message.provider
    puts final_message.api
  end
end

# The stream return value is the same final AssistantMessage.
response # => AssistantMessage
```

If you previously handled every event as if it had `partial`, branch on `event.type == :message_end` first or check `respond_to?(:partial)`.

```ruby
adapter.stream("Hello", model: "gpt-5.4") do |event|
  if event.type == :message_end
    persist(event.message.to_h)
  elsif event.respond_to?(:partial)
    update_ui(event.partial)
  end
end
```

## 8. Update usage accounting keys

Normalized `AssistantMessage#usage` and final stream `event.usage` patches now use provider-independent concise keys:

| 0.5.x key | 0.6.0 key |
|---|---|
| `:input_tokens` | `:input` |
| `:cache_creation_input_tokens` | `:cache_write` |
| `:cache_read_input_tokens` | `:cache_read` |
| `:output_tokens` | `:output` |
| `:reasoning_tokens` | removed |

`reasoning_tokens` was removed because providers expose and calculate reasoning token counts inconsistently. Use the streamed/final `ReasoningContent` blocks for reasoning text, and treat usage as the normalized token buckets above.

```ruby
# Before
result.usage[:input_tokens]
result.usage[:cache_read_input_tokens]
result.usage[:output_tokens]

# After
result.usage[:input]
result.usage[:cache_read]
result.usage[:output]
```

When checking cache behavior, use `usage[:cache_read]` and `usage[:cache_write]`.

## 9. Account for timestamps on streamed messages

`PartialAssistantMessage` and `AssistantMessage` now include a `timestamp` field in Unix milliseconds. Provider-supplied timestamps are preserved when available; otherwise the accumulator assigns one.

```ruby
response = adapter.stream("Hello", model: "gpt-5.4") do |event|
  puts event.partial.timestamp if event.respond_to?(:partial)
end

puts response.timestamp
puts response.to_h[:timestamp]
```

If you instantiate `PartialAssistantMessage` or `AssistantMessage` directly in tests or custom integrations, include `timestamp:`.

## 10. Update custom stream mappers

If you implemented a custom adapter or stream mapper, update it for the new final-message flow.

`LlmGateway::Adapters::StreamMapper` now requires provider/API metadata:

```ruby
mapper = MyStreamMapper.new(provider: "openai", api: "responses")
```

`Adapter#stream` passes these values automatically when it instantiates the configured mapper, but direct mapper construction and custom initializers must accept/pass these keywords.

Custom mappers must also push a final normalized end patch. Use the normalized usage keys shown above for final `usage`.

```ruby
push_patches([
  { type: :message_delta, delta: { stop_reason: "stop" }, usage: { output: 12 } },
  { type: :message_end }
], &block)
```

`StreamMapper#result` now returns the final `AssistantMessage` created by the `:message_end` patch. If a custom mapper never emits `:message_end`, `adapter.stream` will not have a final message to return.

## 11. Cross-provider handoff note

Message sanitization for cross-provider/model handoffs now receives the target model from the request options. When replaying or handing off transcripts across providers/models, pass `model:` explicitly on the destination call so model-specific sanitizer behavior can run.

```ruby
next_response = target_adapter.stream(
  transcript_from_another_provider,
  model: "gpt-5.4"
)
```

## 12. Stream event hash snapshots

Non-final stream events now expose a `partial` assistant message, so `event.to_h` includes an additional `partial` field.

This is additive for normal stream callback consumers:

```ruby
adapter.stream("Hello", model: "gpt-5.4") do |event|
  puts event.type
  puts event.delta if event.respond_to?(:delta)
end
```

If your tests or application code compare full `event.to_h` hashes or snapshot serialized events, update those expectations to include or ignore `partial`.

## Checklist

- [ ] Replace all legacy provider keys with the new provider keys.
- [ ] Remove `model_key:` from `build_provider`, `configure`, and direct client constructors.
- [ ] Remove any direct reads of `client.model_key` / `adapter.client.model_key`.
- [ ] Add `model:` to `chat`, `stream`, Responses/Codex, and embeddings calls where you need a specific model.
- [ ] Update `Prompt` subclasses to configure `provider` and `model` separately.
- [ ] Replace `Prompt.new("model-key")` model lookup usage with explicit provider/model configuration.
- [ ] Replace custom `Prompt#post` usage with `Prompt#stream`.
- [ ] Update stream callbacks to read `event.message` for `:message_end` and `event.partial` only for non-final events.
- [ ] Rename normalized usage lookups to `:input`, `:cache_write`, `:cache_read`, and `:output`; remove `:reasoning_tokens` handling.
- [ ] Include/read `timestamp` on streamed partial and final assistant messages where you construct or persist those objects.
- [ ] Update custom stream mappers to accept `provider:` / `api:`, emit normalized usage keys, and emit `{ type: :message_end }`.
- [ ] For cross-provider handoffs, pass the target `model:` explicitly.
- [ ] Update strict `event.to_h` stream event snapshots/comparisons for the new `partial` field.
