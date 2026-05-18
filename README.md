# llm_gateway

Provide a unified translation interface for LLM Provider API's, While allowing developers to have as much control as possible, This does make it more complicated because we dont want developers to be blocked at using something that the provider supports. As time progress the library will mature and support more responses

## Table of Contents

- [Principles:](#principles)
- [Installation](#installation)
- [Supported Providers](#supported-providers)
- [Quick Start: Streaming (all events)](#quick-start-streaming-all-events)
  - [Stream API without handling events (final result only)](#stream-api-without-handling-events-final-result-only)
- [Migration guides](#migration-guides)
- [Tools](#tools)
  - [Defining Tools](#defining-tools)
  - [Handling Tool Calls](#handling-tool-calls)
- [Image Input](#image-input)
- [Thinking / Reasoning](#thinking--reasoning)
  - [Streaming Thinking Content](#streaming-thinking-content)
  - [How reasoning values are mapped](#how-reasoning-values-are-mapped)
- [Cross-Provider Handoffs](#cross-provider-handoffs)
- [Context Serialization](#context-serialization)
- [OAuth](#oauth)
  - [Get initial tokens (Codex / OpenAI OAuth)](#get-initial-tokens-codex--openai-oauth)
  - [Get initial tokens (Anthropic OAuth)](#get-initial-tokens-anthropic-oauth)
  - [Get a refresh token](#get-a-refresh-token)
  - [Exchange refresh token for access token](#exchange-refresh-token-for-access-token)
  - [Pass access token in provider requests](#pass-access-token-in-provider-requests)
  - [Token refresh responsibility](#token-refresh-responsibility)
    - [Library’s role (llm_gateway)](#librarys-role-llm_gateway)
    - [User/app’s role](#userapps-role)

## Principles:
1. Transcription integrity is most important
2. Input messages must have bidirectional integrity
3. Allow developers as much control as possible

## Installation

```bash
gem install llm_gateway
```

Or add it to your `Gemfile`:

```ruby
gem "llm_gateway"
```

## Supported Providers

| Provider  | Provider Key                 | Auth  | API Surface            |
|-----------|------------------------------|-------|------------------------|
| Anthropic | `anthropic_messages`         | API key | Messages             |
| OpenAI    | `openai_completions`         | API key | Chat Completions     |
| OpenAI    | `openai_responses`           | API key | Responses            |
| OpenAI Codex | `openai_codex`            | OAuth   | Responses            |
| Groq      | `groq_completions`           | API key | Chat Completions     |

Legacy keys (`*_apikey_*`, `*_oauth_*`) are still supported for backward compatibility.

## Quick Start: Streaming (all events)

```ruby
require "llm_gateway"
require "json"

# Build a provider adapter directly (not via prebuilt config)
adapter = LlmGateway.build_provider(
  provider: "openai_responses", # or anthropic_messages, groq_completions, ...
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)

tools = [
  {
    name: "get_time",
    description: "Get the current time",
    input_schema: {
      type: "object",
      properties: {
        timezone: { type: "string", description: "Optional timezone, e.g. America/New_York" }
      }
    }
  }
]

transcript = [
  { role: "user", content: "What time is it? Think briefly, then call get_time." }
]

streamed_tool_args = Hash.new { |h, k| h[k] = +"" }

response = adapter.stream(transcript, tools: tools, reasoning: "high") do |event|
  case event.type
  # AssistantStreamMessageEvent
  when :message_start
    puts "\n[message_start] #{event.delta.inspect}"
  when :message_delta
    puts "\n[message_delta] #{event.delta.inspect} usage+=#{event.usage_increment.inspect}"
  when :message_end
    puts "\n[message_end]"

  # Text events
  when :text_start
    puts "\n[text_start] index=#{event.content_index}"
    print event.delta unless event.delta.empty?
  when :text_delta
    print event.delta
  when :text_end
    puts "\n[text_end] index=#{event.content_index}"

  # Tool-call events
  when :tool_start
    puts "\n[tool_start] id=#{event.id} name=#{event.name} index=#{event.content_index}"
  when :tool_delta
    streamed_tool_args[event.content_index] << event.delta
    print event.delta
  when :tool_end
    puts "\n[tool_end] index=#{event.content_index}"
    begin
      puts "tool args: #{JSON.parse(streamed_tool_args[event.content_index])}"
    rescue JSON::ParserError
      puts "tool args (partial/raw): #{streamed_tool_args[event.content_index]}"
    end

  # Reasoning events
  when :reasoning_start
    puts "\n[reasoning_start] sig=#{event.respond_to?(:signature) ? event.signature : ""}"
    print event.delta
  when :reasoning_delta
    print event.delta
  when :reasoning_end
    puts "\n[reasoning_end]"

  end
end

# Final AssistantMessage (assembled from the stream)
puts "\n\n=== Final assistant message ==="
puts "id: #{response.id}"
puts "model: #{response.model}"
puts "provider/api: #{response.provider}/#{response.api}"
puts "role: #{response.role}"
puts "stop_reason: #{response.stop_reason}"
puts "error_message: #{response.error_message.inspect}" if response.error_message
puts "usage: #{response.usage.inspect}"

response.content.each do |block|
  case block.type
  when "text"
    puts "text: #{block.text}"
  when "reasoning"
    puts "reasoning: #{block.reasoning}"
    puts "signature: #{block.signature}" if block.respond_to?(:signature) && block.signature
  when "tool_use"
    puts "tool_use: #{block.name}(#{block.input.inspect}) id=#{block.id}"
  end
end
```

Stream callback event families:
- `AssistantStreamMessageEvent`: `:message_start`, `:message_delta`, `:message_end`
- `AssistantStreamEvent` (and subclasses):
  - Text: `:text_start`, `:text_delta`, `:text_end`
  - Tool call: `:tool_start`, `:tool_delta`, `:tool_end`
  - Reasoning: `:reasoning_start`, `:reasoning_delta`, `:reasoning_end`

### Stream API without handling events (final result only)

If you only care about the final `AssistantMessage`, call `stream` without a block:

```ruby
require "llm_gateway"

adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)

result = adapter.stream("Write one short sentence about Ruby.")

puts result.role         # "assistant"
puts result.stop_reason  # "stop" (usually)
puts result.usage.inspect

text = result.content
  .select { |block| block.type == "text" }
  .map(&:text)
  .join

puts text
```

## Migration guides

- [Migrating from `chat` to `stream`](docs/chat-to-stream-migration.md) — use `stream` without a block when you only need the final response.

## Tools

### Defining Tools

```ruby
weather_tool = {
  name: "get_weather",
  description: "Get current weather for a location",
  input_schema: {
    type: "object",
    properties: {
      location: { type: "string", description: "City name or coordinates" },
      units: {
        type: "string",
        enum: ["celsius", "fahrenheit"],
        default: "celsius"
      }
    },
    required: ["location"]
  }
}
```

### Handling Tool Calls

Use `stream` without a block, inspect returned `tool_use` blocks, execute tools, append `tool_result`, then continue:

```ruby
require "llm_gateway"
require "json"

adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)

weather_tool = {
  name: "get_weather",
  description: "Get current weather for a location",
  input_schema: {
    type: "object",
    properties: {
      location: { type: "string" },
      units: { type: "string", enum: ["celsius", "fahrenheit"], default: "celsius" }
    },
    required: ["location"]
  }
}

def execute_weather_api(args)
  # Replace with real API call
  {
    location: args[:location] || args["location"],
    units: args[:units] || args["units"] || "celsius",
    temperature: 14,
    condition: "Cloudy"
  }
end

transcript = [
  { role: "user", content: "What is the weather in London?" }
]

# 1) First model pass (stream API, no event block)
response = adapter.stream(transcript, tools: [weather_tool])
transcript << response.to_h

# 2) Execute tool calls returned by the model
response.content.each do |block|
  next unless block.type == "tool_use"

  tool_result = execute_weather_api(block.input)

  transcript << {
    role: "developer",
    content: [
      {
        type: "tool_result",
        tool_use_id: block.id,
        content: JSON.generate(tool_result)
      }
    ]
  }
end

# 3) Continue the conversation after tool execution
if response.content.any? { |b| b.type == "tool_use" }
  final_response = adapter.stream(transcript, tools: [weather_tool])

  final_text = final_response.content
    .select { |b| b.type == "text" }
    .map(&:text)
    .join

  puts final_text
end
```

Notes:
- Tool calls are returned as `ToolCall` blocks with `type: "tool_use"`, `id`, `name`, and `input`.
- Tool results are sent back in the transcript as `{ type: "tool_result", tool_use_id:, content: }` blocks.
- For multimodal-capable models, `tool_result` content can include image blocks when supported by the provider/model.

## Image Input

Send images by including an `image` content block in a user message.

```ruby
require "llm_gateway"
require "base64"

adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)

image_b64 = Base64.strict_encode64(File.binread("./chart.png"))

message = [
  {
    role: "user",
    content: [
      { type: "text", text: "What do you see in this image?" },
      { type: "image", data: image_b64, media_type: "image/png" }
    ]
  }
]

result = adapter.stream(message) # stream API, no event block

text = result.content
  .select { |b| b.type == "text" }
  .map(&:text)
  .join

puts text
```

Tip: use a model/provider combination that supports vision input.

## Thinking / Reasoning

You can request higher-effort reasoning by passing `reasoning:` to `stream`.

```ruby
require "llm_gateway"

adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)

result = adapter.stream(
  "Think step by step and then compute 482 * 17.",
  reasoning: "high"
)

puts "stop_reason: #{result.stop_reason}"
puts "usage: #{result.usage.inspect}" # may include reasoning_tokens depending on provider

result.content.each do |block|
  case block.type
  when "reasoning"
    puts "[reasoning] #{block.reasoning}"
    puts "[signature] #{block.signature}" if block.respond_to?(:signature) && block.signature
  when "text"
    puts "[text] #{block.text}"
  end
end
```

### Streaming Thinking Content

If you want incremental thinking/reasoning tokens as they arrive, pass a block to `stream` and handle reasoning events:

```ruby
reasoning_text = +""

result = adapter.stream("Solve 99 * 99 with brief reasoning.", reasoning: "high") do |event|
  case event.type
  when :reasoning_start
    print "\n[thinking start]\n"
    reasoning_text << event.delta
  when :reasoning_delta
    reasoning_text << event.delta
    print event.delta
  when :reasoning_end
    print "\n[thinking end]\n"
  end
end

puts "\nCollected reasoning chars: #{reasoning_text.length}"
puts "Final stop_reason: #{result.stop_reason}"
```

### How reasoning values are mapped

`llm_gateway` normalizes provider-specific reasoning/thinking output into shared structures:

- Stream events:
  - `:reasoning_start/:reasoning_delta/:reasoning_end`
- Final content block:
  - `ReasoningContent` with `type: "reasoning"`
  - fields: `reasoning` and optional `signature`
- Usage accounting:
  - normalized in `result.usage` when provided by the upstream API
  - may include `:reasoning_tokens` plus standard token counters

In practice this means you can:
- listen to `:reasoning_*` stream event variants, and
- always read final reasoning text from `result.content` blocks where `block.type == "reasoning"`.

Notes:
- Reasoning output appears as `ReasoningContent` blocks with `type: "reasoning"`.
- Some providers/models expose explicit reasoning content; others may only reflect reasoning effort in usage fields.
- In streamed callbacks, reasoning events are emitted as `:reasoning_*` variants.

## Cross-Provider Handoffs

Internally, `llm_gateway` handles handoffs by normalizing message history into a provider-agnostic shape, then remapping that shape to the target provider API on each request.

What happens under the hood on `stream`/`chat`:

1. **Normalize input**
   - String input is converted to a user message.
   - `system` is normalized into system message objects.
   - Prior assistant turns (including `response.to_h`) are treated as structured transcript entries.

2. **Map into canonical gateway format**
   - Provider-specific differences (content block names, tool-call shapes, reasoning/thinking variants) are unified into shared structs.

3. **Sanitize for target provider/model**
   - Before sending, messages are sanitized for the destination provider/API/model.
   - Unsupported or provider-specific fields are adjusted/translated where possible.

4. **Map to outbound provider payload**
   - The adapter input mapper converts canonical messages/tools/options into the exact wire format expected by the selected provider endpoint.

5. **Map response back to canonical output**
   - Stream chunks are mapped into normalized stream events.
   - Final output is accumulated into a normalized `AssistantMessage` (`id`, `model`, `usage`, `stop_reason`, `content`, etc.).

Why this matters:
- A transcript produced by one provider can be reused with another provider without manually rewriting message structure.
- Tool calls/reasoning/text are exposed through a consistent API even when upstream event formats differ.
- Your app can keep one conversation state format while switching providers for cost, latency, capability, or reliability reasons.

## Context Serialization

`llm_gateway` contexts are plain Ruby hashes/arrays, so they can be serialized to JSON and restored later.

```ruby
require "llm_gateway"
require "json"

adapter = LlmGateway.build_provider(
  provider: "openai_apikey_responses",
  api_key: ENV.fetch("OPENAI_API_KEY"),
  model_key: "gpt-5.4"
)

# Build context (transcript)
transcript = [
  { role: "user", content: "Plan a 3-day trip to Tokyo." }
]

# Run one turn and persist assistant output
first = adapter.stream(transcript)
transcript << first.to_h

# Serialize (store in DB/file/cache)
json_context = JSON.generate(transcript)

# ...later / elsewhere...
restored_transcript = JSON.parse(json_context)

# Continue conversation from restored context
restored_transcript << { role: "user", content: "Now make it budget-friendly." }
second = adapter.stream(restored_transcript)

puts second.content.select { |b| b.type == "text" }.map(&:text).join
```

What to persist:
- full transcript array (including assistant messages from `response.to_h`)
- any tool result messages you appended
- optional app metadata (user id, conversation id, timestamps) alongside the transcript

Tip: if you serialize to JSON, keys become strings on parse; `llm_gateway` accepts standard hash input and normalizes internally.

## OAuth

Use OAuth-capable providers (for example `openai_codex` and `anthropic_oauth_messages`) by supplying an `access_token` when building the adapter.

### Get initial tokens (Codex / OpenAI OAuth)

```ruby
require "llm_gateway"

flow = LlmGateway::Clients::OpenAI::OAuthFlow.new

# 1) Start flow (generate auth URL + PKCE verifier + state)
start = flow.start
puts "Open in browser: #{start[:authorization_url]}"

# 2) After user auth, paste redirect URL (or raw code)
# Example: http://localhost:1455/auth/callback?code=...&state=...
print "Paste callback URL or code: "
input = STDIN.gets&.strip

# 3) Exchange for initial tokens
tokens = flow.exchange_code(input, start[:code_verifier], expected_state: start[:state])

puts tokens
# => {
#   access_token: "...",
#   refresh_token: "...",
#   expires_at: <Time>,
#   account_id: "..."
# }
```

### Get initial tokens (Anthropic OAuth)

```ruby
require "llm_gateway"

flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new

# 1) Start flow (auth URL + PKCE verifier + state)
start = flow.start
puts "Open in browser: #{start[:authorization_url]}"

# 2) After user auth, paste callback URL (or code)
# Example callback contains ?code=...&state=...
print "Paste callback URL or code: "
input = STDIN.gets&.strip

# 3) Exchange for initial tokens
tokens = flow.exchange_code(input, start[:code_verifier], state: start[:state])

puts tokens
# => {
#   access_token: "...",
#   refresh_token: "...",
#   expires_at: <Time>
# }
```

### Get a refresh token

### Exchange refresh token for access token

Use the built-in token managers in this repo. `on_token_refresh` block will be called when the refresh token is updated and should be persisted.

OpenAI Codex OAuth:

```ruby
require "llm_gateway"

manager = LlmGateway::Clients::OpenAI::TokenManager.new(
  refresh_token: stored_refresh_token,
  access_token: stored_access_token,   # optional
  expires_at: stored_expires_at         # optional
)

manager.on_token_refresh = lambda do |new_access_token, new_refresh_token, new_expires_at|
  # Persist updated credentials in your DB/secrets store
end

current_access_token = manager.access_token
```

Anthropic OAuth:

```ruby
require "llm_gateway"

manager = LlmGateway::Clients::ClaudeCode::TokenManager.new(
  refresh_token: stored_refresh_token,
  access_token: stored_access_token,    # optional
  expires_at: stored_expires_at,        # optional
  client_id: ENV.fetch("ANTHROPIC_CLIENT_ID"),
  client_secret: ENV["ANTHROPIC_CLIENT_SECRET"] # optional depending on app setup
)

manager.on_token_refresh = lambda do |new_access_token, new_refresh_token, new_expires_at|
  # Persist updated credentials
end

current_access_token = manager.access_token
```

### Pass access token in provider requests

Build the provider with the current access token:

```ruby
adapter = LlmGateway.build_provider(
  provider: "openai_codex",
  access_token: current_access_token,
  model_key: "gpt-5.4"
)

result = adapter.stream("Hello from OAuth auth")
puts result.content.select { |b| b.type == "text" }.map(&:text).join
```

If your app refreshes tokens in the background, rebuild the adapter (or recreate client state) with the newest `access_token` before subsequent calls.

### Token refresh responsibility

#### Library’s role (llm_gateway)

- Provides token manager helpers.
- Detects expiry from expires_at.
- Refreshes access token when asked (ensure_valid_token / refresh methods).
- Returns updated token values and triggers on_token_refresh callback after successful refresh.
- Uses whatever access token you pass into provider requests.

#### User/app’s role

- Persist tokens securely (DB/secrets store).
- Store and pass access_token, refresh_token, expires_at into the token manager.
- Implement on_token_refresh to save updated credentials.
- Decide refresh/retry policy at app level (e.g., retry failed request after refresh when appropriate).
- Rebuild client/provider state with latest access token for future calls.

In short: library executes refresh mechanics; your app owns token lifecycle persistence and operational policy.

## Contributing

### Recording VCR cassettes

Live integration tests use VCR cassettes stored under `test/fixtures/vcr_cassettes`. To record a new cassette, run the target test with real provider credentials available in your environment or `.env`:

```bash
bundle exec ruby -Itest test/integration/live/stream_test.rb
```

Cassette names are derived from the test file and test name, with VCR sanitizing path segments such as `stream_test.rb` to `stream_test_rb`.

For OAuth-backed providers (`anthropic_oauth_messages`, `openai_oauth_codex`), the live test helper only loads real OAuth credentials while the cassette is being recorded. Once the cassette exists, replay uses placeholder tokens/account IDs so the test suite can run without local OAuth state. API-key providers still require the relevant API key when recording. Sensitive authorization headers and selected response headers are redacted before cassettes are written.

Some tests pass `redact_request_body: true` to `with_vcr_adapter`; those cassettes match on method and URI only and replace large request bodies with `"<huge prompt body redacted>"`.
