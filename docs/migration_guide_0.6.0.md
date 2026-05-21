# Migration Guide: 0.5.0 to 0.6.0

This guide covers user-facing changes between `v0.5.0` and the latest commit on the 0.6.0 branch.

## Summary

0.6.0 separates provider authentication/configuration from model selection.

- Provider config now contains only provider/auth settings such as `provider`, `api_key`, `access_token`, and `account_id`.
- `model_key` is no longer accepted in provider/client configuration.
- Pass the model per request with `model:` when calling `chat`, `stream`, Responses/Codex methods, or embeddings.
- Legacy provider keys such as `openai_apikey_responses` were removed. Use the shorter provider keys.
- `LlmGateway::Prompt` now accepts/configures a provider and model separately, and uses `stream` internally.

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

## 5. OAuth provider names

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

## 6. Cross-provider handoff note

Message sanitization for cross-provider/model handoffs now receives the target model from the request options. When replaying or handing off transcripts across providers/models, pass `model:` explicitly on the destination call so model-specific sanitizer behavior can run.

```ruby
next_response = target_adapter.stream(
  transcript_from_another_provider,
  model: "gpt-5.4"
)
```

## Checklist

- [ ] Replace all legacy provider keys with the new provider keys.
- [ ] Remove `model_key:` from `build_provider`, `configure`, and direct client constructors.
- [ ] Add `model:` to `chat`, `stream`, Responses/Codex, and embeddings calls where you need a specific model.
- [ ] Update `Prompt` subclasses to configure `provider` and `model` separately.
- [ ] Replace custom `Prompt#post` usage with `Prompt#stream`.
- [ ] For cross-provider handoffs, pass the target `model:` explicitly.
