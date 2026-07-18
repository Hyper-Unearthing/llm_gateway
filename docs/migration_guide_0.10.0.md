# Migration guide: v0.9.0 to v0.10.0

## Build adapters directly

`LlmGateway.build_provider`, `LlmGateway.configure`, `configured_clients`, and `ProviderRegistry` were removed. Build and retain the adapter your application needs:

```ruby
# Before
adapter = LlmGateway.build_provider(provider: "openai_responses", api_key: key)

# After
adapter = LlmGateway::Adapters::OpenAI::Responses.build(api_key: key)
```

Use `Anthropic::Messages`, `OpenAI::ChatCompletions`, `OpenAI::Responses`, `OpenAICodex::Responses`, or `Groq::ChatCompletions`. `Adapter.build` accepts only client/transport configuration, not `model:` or `model_key:`.

## Pass model definitions, not strings

`stream` now requires a catalog model definition. Fetch one and reuse it:

```ruby
model = LlmGateway.models.fetch("openai/gpt-5.4")
adapter.stream("Hello", model: model)
```

For a newly released or custom model, register a `LlmGateway::Models::Definition` through `LlmGateway.models.register(...)` before using it. The adapter and model providers must match.

## Update Prompt and Harness setup

`Prompt` accepts `adapter:` instead of `provider:`. Set `self.adapter` on subclasses or pass `adapter:` to `new`, `run`, or `stream`.

A `Harness` also requires an adapter, while its model and reasoning live in the session:

```ruby
session.change_model(model)
session.change_reasoning("high")
harness = MyHarness.new(session, adapter: adapter)
```

Use `harness.change_adapter(new_adapter, model: new_model)` when switching providers.

## Update proxy clients

Build proxies with `adapter:` rather than `target_provider:`. Pass an adapter definition, class, or instance:

```ruby
proxy = LlmGateway::Proxy.build(
  url: url,
  adapter: LlmGateway::Adapters::OpenAI::Responses
)
```

The proxy protocol now uses allowlisted hyphenated adapter names internally.
