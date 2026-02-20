# Extending LlmGateway with Custom Clients and Adapters

LlmGateway has a layered architecture that separates **transport** (clients) from **format translation** (adapters). You can build custom clients and adapters either inside the gem or externally in your own project by importing and extending the base classes.

## Architecture Overview

```
Your Code
    │
    ▼
┌─────────┐      ┌──────────────┐      ┌──────────────┐
│ Adapter  │ ───▶ │ InputMapper  │ ───▶ │    Client     │ ───▶ LLM API
│          │ ◀─── │ OutputMapper │ ◀─── │              │ ◀───
└─────────┘      └──────────────┘      └──────────────┘
```

**Client** — handles HTTP transport, authentication, headers, and error handling. Talks to a specific API endpoint in its native format.

**Adapter** — wraps a client and translates between LlmGateway's normalized message format and the provider's native format. Contains an InputMapper (normalize → native) and an OutputMapper (native → normalize).

**ClientBuilder** — factory that pairs a client with the right adapter based on config. Optional — you can assemble client + adapter manually.

### Normalized Message Format

All adapters translate to/from this common shape:

```ruby
# Input (what your code sends)
{
  messages: [
    { role: "user", content: [{ type: "text", text: "Hello" }] },
    { role: "assistant", content: [
      { type: "text", text: "Hi!" },
      { type: "tool_use", id: "call_1", name: "bash", input: { command: "ls" } }
    ]},
    { role: "user", content: [
      { type: "tool_result", tool_use_id: "call_1", content: "file.txt" }
    ]}
  ],
  tools: [
    { name: "bash", description: "Run a command", input_schema: { type: "object", ... } }
  ],
  system: [
    { role: "system", content: "You are helpful." }
  ]
}

# Output (what your code receives)
{
  id: "msg_abc",
  model: "gpt-4o",
  usage: { prompt_tokens: 10, completion_tokens: 20 },
  choices: [
    {
      role: "assistant",
      content: [
        { type: "text", text: "Here's the result" },
        { type: "tool_use", id: "call_2", name: "read", input: { path: "foo.rb" } }
      ]
    }
  ]
}
```

This format is Claude-flavored (content arrays, `tool_use`/`tool_result` blocks). The adapters handle converting to/from OpenAI's format (tool_calls, separate tool messages) or any other provider format.

---

## Part 1: Building a Custom Client

A client is a subclass of `LlmGateway::BaseClient`. It handles:

- Setting `@base_endpoint`
- Implementing `#chat` to build the request body and call `post`/`post_stream`
- Implementing `#build_headers` for authentication
- Optionally implementing `#handle_client_specific_errors`

### Minimal Example

```ruby
require "llm_gateway"

class MyClient < LlmGateway::BaseClient
  def initialize(model_key: "my-model", api_key: ENV["MY_API_KEY"])
    @base_endpoint = "https://api.myprovider.com/v1"
    super(model_key: model_key, api_key: api_key)
  end

  def chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096, &block)
    body = {
      model: model_key,
      messages: (system || []) + messages,
      max_tokens: max_completion_tokens
    }
    body[:tools] = tools if tools

    if block_given?
      body[:stream] = true
      post_stream("chat/completions", body, &block)
    else
      post("chat/completions", body)
    end
  end

  private

  def build_headers
    {
      "content-type" => "application/json",
      "Authorization" => "Bearer #{api_key}"
    }
  end

  def handle_client_specific_errors(response, error)
    error_code = error["code"]
    case response.code.to_i
    when 429
      raise LlmGateway::Errors::RateLimitError.new(error["message"], error_code)
    end
    raise LlmGateway::Errors::APIStatusError.new(error["message"], error_code)
  end
end
```

### What BaseClient Gives You

The base class (`lib/llm_gateway/base_client.rb`) provides:

| Method | Purpose |
|---|---|
| `post(url_part, body, extra_headers)` | POST JSON, return parsed response |
| `post_stream(url_part, body, extra_headers, &block)` | POST with SSE streaming, yields `{ event:, data: }` hashes |
| `get(url_part, extra_headers)` | GET request |
| `post_file(url_part, content, filename, ...)` | Multipart file upload |
| `process_response(response)` | Parse JSON or return raw body, handle errors |
| `handle_error(response)` | Dispatch to `handle_client_specific_errors`, then map HTTP status to error classes |
| `parse_sse_stream(response, &block)` | Parse `event:` / `data:` SSE lines, yield parsed hashes |

All HTTP methods use SSL, 480s read timeout, 10s connect timeout.

### Extending an Existing Client

To add OAuth or custom auth to an existing provider, subclass its client:

```ruby
class MyOAuthOpenAi < LlmGateway::Clients::OpenAi
  def initialize(model_key: "gpt-4o", access_token:, refresh_token: nil)
    @access_token = access_token
    @refresh_token = refresh_token
    super(model_key: model_key, api_key: access_token)
  end

  private

  def build_headers
    {
      "content-type" => "application/json",
      "Authorization" => "Bearer #{@access_token}"
    }
  end
end
```

### Real-World Example: ClaudeCode Client

`Clients::ClaudeCode` extends `Clients::Claude` to add:

- OAuth token management (`TokenManager`)
- Auto-refresh on `AuthenticationError` via `post_with_retry` / `post_stream_with_retry`
- Custom headers (`anthropic-beta`, `user-agent`, bearer auth instead of x-api-key)
- A system prompt identity block prepended to every request

See `lib/llm_gateway/clients/claude_code.rb`.

---

## Part 2: Building a Custom Adapter

An adapter wraps a client and provides format translation via mappers.

### Adapter Base Class

`LlmGateway::Adapters::Adapter` (`lib/llm_gateway/adapters/adapter.rb`) handles:

1. Normalizing input (string messages → arrays, string system → array)
2. Calling `input_mapper.map(data)` to translate to provider format
3. Calling `client.chat(...)` with the mapped input
4. Calling `output_mapper.map(result)` to translate the response back
5. For streaming: using a `stream_output_mapper` to accumulate SSE events

```ruby
class Adapter
  def initialize(client, input_mapper:, output_mapper:, file_output_mapper: nil, stream_output_mapper: nil)

  def chat(message, response_format: "text", tools: nil, system: nil, &block)
    # normalize → input_mapper.map → client.chat → output_mapper.map
  end
end
```

### Minimal Adapter Example

```ruby
class MyAdapter < LlmGateway::Adapters::Adapter
  def initialize(client)
    super(
      client,
      input_mapper: MyInputMapper,
      output_mapper: MyOutputMapper,
      stream_output_mapper: MyStreamOutputMapper  # optional, needed for streaming
    )
  end
end
```

### InputMapper

Translates from normalized format to the provider's native format. Must implement `self.map(data)` returning `{ messages:, response_format:, tools:, system: }`.

```ruby
class MyInputMapper
  def self.map(data)
    {
      messages: map_messages(data[:messages]),
      response_format: data[:response_format],
      tools: map_tools(data[:tools]),
      system: map_system(data[:system])
    }
  end

  private

  def self.map_messages(messages)
    # Transform normalized messages to provider format
    # e.g., convert tool_use/tool_result blocks to provider's tool call format
    messages
  end

  def self.map_tools(tools)
    return tools unless tools
    # Transform tool definitions
    # Normalized: { name:, description:, input_schema: }
    # OpenAI:     { type: "function", function: { name:, description:, parameters: } }
    tools.map do |tool|
      { type: "function", function: { name: tool[:name], description: tool[:description], parameters: tool[:input_schema] } }
    end
  end

  def self.map_system(system)
    system
  end
end
```

### OutputMapper

Translates provider response to normalized format. Must implement `self.map(data)` returning `{ id:, model:, usage:, choices: [{ role:, content: [...] }] }`.

```ruby
class MyOutputMapper
  def self.map(data)
    {
      id: data[:id],
      model: data[:model],
      usage: data[:usage],
      choices: data[:choices].map do |choice|
        message = choice[:message] || {}
        content = []
        content << { type: "text", text: message[:content] } if message[:content]

        # Convert tool_calls to tool_use blocks
        (message[:tool_calls] || []).each do |tc|
          content << {
            type: "tool_use",
            id: tc[:id],
            name: tc[:function][:name],
            input: JSON.parse(tc[:function][:arguments], symbolize_names: true)
          }
        end

        { role: message[:role], content: content }
      end
    }
  end
end
```

### StreamOutputMapper

Accumulates SSE events during streaming and produces a final message. Must implement:

- `#map_event(sse_event)` — process one SSE event, return a normalized event (or nil to skip). Common return types: `{ type: :text_delta, text: "..." }`, `{ type: :tool_use, id:, name:, input: }`, `{ type: :thinking_delta, thinking: "..." }`
- `#to_message` — return the fully accumulated response in the same shape as the provider's non-streaming response (this gets passed to `output_mapper.map`)

```ruby
class MyStreamOutputMapper
  def initialize
    @id = nil
    @model = nil
    @content_text = +""
    @tool_calls = []
    @usage = {}
  end

  def map_event(sse_event)
    data = sse_event[:data]
    return nil if data == { raw: "[DONE]" }

    @id ||= data[:id]
    @model ||= data[:model]
    @usage = data[:usage] if data[:usage]

    delta = data.dig(:choices, 0, :delta)
    return nil unless delta

    if delta[:content]
      @content_text << delta[:content]
      return { type: :text_delta, text: delta[:content] }
    end

    nil
  end

  def to_message
    # Return shape that output_mapper expects (provider's native format)
    {
      id: @id, model: @model, usage: @usage,
      choices: [{ message: { role: "assistant", content: @content_text, tool_calls: @tool_calls } }]
    }
  end
end
```

### BidirectionalMessageMapper (Optional Pattern)

Several adapters use a `BidirectionalMessageMapper` — a single class that handles both directions (`:in` and `:out`) for content block translation. This avoids duplicating logic between InputMapper and OutputMapper.

```ruby
class BidirectionalMessageMapper
  def initialize(direction)  # LlmGateway::DIRECTION_IN or DIRECTION_OUT
    @direction = direction
  end

  def map_content(content)
    case content[:type]
    when "tool_use"
      @direction == LlmGateway::DIRECTION_IN ? to_native_tool_call(content) : from_native_tool_call(content)
    when "tool_result"
      to_native_tool_result(content)
    else
      content
    end
  end
end
```

The InputMapper creates one with `DIRECTION_IN`, the OutputMapper with `DIRECTION_OUT`.

### Reusing Existing Mappers

If your provider uses the same format as an existing one (e.g., OpenAI-compatible), inherit:

```ruby
# Groq uses OpenAI format, so its mappers just inherit
class Groq::InputMapper < OpenAi::ChatCompletions::InputMapper
  private
  def self.map_system(system)
    system  # Groq doesn't convert system→developer
  end
end

class Groq::OutputMapper < OpenAi::ChatCompletions::OutputMapper
end
```

---

## Part 3: Assembling Client + Adapter

### Option A: Manual Assembly (External Project)

You don't need `ClientBuilder` or the `PROVIDERS` registry. Just instantiate a client and wrap it in an adapter:

```ruby
require "llm_gateway"

# 1. Create client
client = LlmGateway::Clients::OpenAi.new(model_key: "gpt-4o", api_key: "sk-...")

# 2. Wrap in adapter
adapter = LlmGateway::Adapters::OpenAi::ChatCompletionsAdapter.new(client)

# 3. Use it
result = adapter.chat("What is 2+2?", tools: my_tools, system: "You are helpful.")
```

Or with a custom client:

```ruby
client = MyOAuthOpenAi.new(model_key: "gpt-4o", access_token: token)
adapter = LlmGateway::Adapters::OpenAi::ChatCompletionsAdapter.new(client)
```

Or with fully custom client + adapter:

```ruby
client = MyClient.new(model_key: "my-model", api_key: key)
adapter = MyAdapter.new(client)
```

### Option B: Register in ClientBuilder (Inside the Gem)

Add your provider to the `PROVIDERS` hash in `lib/llm_gateway/client_builder.rb`:

```ruby
PROVIDERS = {
  # ...existing providers...
  "myprovider" => {
    client: Clients::MyProvider,
    default_adapter: Adapters::MyProvider::ChatCompletionsAdapter
  }
}
```

For providers with multiple auth types (like Anthropic with api_key vs oauth):

```ruby
"myprovider" => {
  "api_key" => {
    client: Clients::MyProvider,
    default_adapter: Adapters::MyProvider::Adapter
  },
  "oauth" => {
    client: Clients::MyProviderOAuth,
    default_adapter: Adapters::MyProviderOAuth::Adapter
  }
}
```

Then use via `LlmGateway.build`:

```ruby
adapter = LlmGateway.build(provider: "myprovider", model: "my-model", key: "sk-...")
```

### Option C: Convenience Builder (External Project)

Create a module-level `build` method for ergonomics:

```ruby
module MyProvider
  def self.build(access_token:, model: "my-model", **opts)
    client = Client.new(model_key: model, access_token: access_token, **opts)
    Adapter.new(client)
  end
end

# Usage
adapter = MyProvider.build(access_token: token, model: "gpt-4o")
adapter.chat("Hello", tools: tools, system: system)
```

---

## Part 4: Full External Client Walkthrough

This walks through building an OpenAI OAuth client **outside** the gem (in your own project), reusing llm_gateway components.

### File Structure

```
my_project/
├── lib/
│   └── openai_oauth/
│       ├── client.rb             # Extends LlmGateway::Clients::OpenAi
│       ├── adapter.rb            # Wraps client with OpenAI chat completions mappers
│       ├── oauth_flow.rb         # PKCE + token exchange
│       ├── token_manager.rb      # Token refresh logic
│       └── stream_output_mapper.rb  # SSE accumulator (if streaming needed)
│   └── openai_oauth.rb          # Entry point + build helper
├── Gemfile                      # gem 'llm_gateway', path: '../llm_gateway'
```

### Step 1: Client

Extend the existing OpenAI client, override auth headers:

```ruby
# lib/openai_oauth/client.rb
require "llm_gateway"

module OpenAiOAuth
  class Client < LlmGateway::Clients::OpenAi
    attr_reader :token_manager

    def initialize(model_key: "gpt-4o", access_token:, refresh_token: nil, expires_at: nil)
      @oauth_access_token = access_token

      if refresh_token
        @token_manager = TokenManager.new(
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at
        )
      end

      super(model_key: model_key, api_key: access_token)
    end

    def chat(messages, **kwargs, &block)
      @token_manager&.ensure_valid_token
      @oauth_access_token = @token_manager&.access_token || @oauth_access_token
      super
    end

    private

    def build_headers
      {
        "content-type" => "application/json",
        "Authorization" => "Bearer #{@oauth_access_token}"
      }
    end
  end
end
```

### Step 2: Adapter

Reuse the existing OpenAI chat completions mappers — they already handle the format:

```ruby
# lib/openai_oauth/adapter.rb
require "llm_gateway"

module OpenAiOAuth
  class Adapter < LlmGateway::Adapters::Adapter
    def initialize(client)
      super(
        client,
        input_mapper:  LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper,
        output_mapper: LlmGateway::Adapters::OpenAi::ChatCompletions::OutputMapper
      )
    end
  end
end
```

### Step 3: Build Helper

```ruby
# lib/openai_oauth.rb
module OpenAiOAuth
  def self.build(access_token:, refresh_token: nil, expires_at: nil, model: "gpt-4o")
    client = Client.new(
      model_key: model,
      access_token: access_token,
      refresh_token: refresh_token,
      expires_at: expires_at
    )
    Adapter.new(client)
  end
end
```

### Step 4: Use It

```ruby
adapter = OpenAiOAuth.build(access_token: token, refresh_token: refresh, model: "gpt-4o")

result = adapter.chat(
  [{ role: "user", content: [{ type: "text", text: "Hello" }] }],
  tools: [{ name: "bash", description: "Run command", input_schema: { ... } }],
  system: [{ role: "system", content: "You are helpful." }]
)

puts result[:choices][0][:content]
# => [{ type: "text", text: "Hi there!" }]
```

---

## Existing Providers Reference

| Provider | Client | Adapter | API Format |
|---|---|---|---|
| Anthropic (API key) | `Clients::Claude` | `Adapters::Claude::MessagesAdapter` | Claude Messages API |
| Anthropic (OAuth) | `Clients::ClaudeCode` | `Adapters::ClaudeCode::MessagesAdapter` | Claude Messages API |
| OpenAI | `Clients::OpenAi` | `Adapters::OpenAi::ChatCompletionsAdapter` | Chat Completions |
| OpenAI | `Clients::OpenAi` | `Adapters::OpenAi::ResponsesAdapter` | Responses API |
| Groq | `Clients::Groq` | `Adapters::Groq::ChatCompletionsAdapter` | OpenAI-compatible |

### Mapper Inheritance Tree

```
Claude::InputMapper
  └── ClaudeCode::InputMapper

Claude::OutputMapper
  └── ClaudeCode::OutputMapper

OpenAi::ChatCompletions::InputMapper
  └── Groq::InputMapper

OpenAi::ChatCompletions::OutputMapper
  └── Groq::OutputMapper
```

If your provider is OpenAI-compatible, inherit from `OpenAi::ChatCompletions::*`. If it's Claude-compatible, inherit from `Claude::*`. Otherwise, write your own mappers from scratch.

---

## Error Handling

Clients raise typed errors from `LlmGateway::Errors`:

| Error | HTTP Status | When |
|---|---|---|
| `BadRequestError` | 400 | Malformed request |
| `AuthenticationError` | 401 | Invalid/expired token |
| `PermissionDeniedError` | 403 | Insufficient permissions |
| `NotFoundError` | 404 | Bad endpoint |
| `RateLimitError` | 429 | Rate limited |
| `OverloadError` | 503 | Server overloaded |
| `PromptTooLong` | 400 | Input too large |

Override `handle_client_specific_errors(response, error)` in your client to map provider-specific error codes before the generic HTTP status mapping kicks in. Raise `APIStatusError` for anything you don't handle specifically — `BaseClient#handle_error` will re-map it based on HTTP status.
