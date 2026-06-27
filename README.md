# llm_gateway

Provide a unified translation interface for LLM Provider API's, While allowing developers to have as much control as possible, This does make it more complicated because we dont want developers to be blocked at using something that the provider supports. As time progress the library will mature and support more responses

## Table of Contents

- [Principles:](#principles)
- [Installation](#installation)
- [Supported Providers](#supported-providers)
- [Stream Options](#stream-options)
  - [Managed cross-provider options](#managed-cross-provider-options)
  - [Provider-specific options](#provider-specific-options)
- [Quick Start: Streaming (all events)](#quick-start-streaming-all-events)
  - [Stream API without handling events (final result only)](#stream-api-without-handling-events-final-result-only)
- [Prompt classes](#prompt-classes)
- [Migration guides](#migration-guides)
- [Tools](#tools)
  - [Defining Tools](#defining-tools)
  - [Handling Tool Calls](#handling-tool-calls)
  - [Server Tool Use](#server-tool-use)
- [Agents](#agents)
  - [Agent events](#agent-events)
  - [Session managers and persistence](#session-managers-and-persistence)
  - [Queues, steering, and follow-ups](#queues-steering-and-follow-ups)
  - [Compaction](#compaction)
  - [Built-in agent tools](#built-in-agent-tools)
- [Image Input](#image-input)
- [Thinking / Reasoning](#thinking--reasoning)
  - [Streaming Thinking Content](#streaming-thinking-content)
  - [How reasoning values are mapped](#how-reasoning-values-are-mapped)
- [Cross-Provider Handoffs](#cross-provider-handoffs)
- [Context Serialization](#context-serialization)
  - [Message metadata](#message-metadata)
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

Provider configuration only contains auth/client settings (for example `api_key` or `access_token`). Pass the model per request with `model:` when calling `chat` or `stream`.

## Stream Options

Pass options to `stream` as keyword arguments alongside `tools:` and `system:`:

```ruby
result = adapter.stream(
  transcript,
  system: "You are concise.",
  reasoning: "high",
  cache_key: "conversation-123",
  cache_retention: "short",
  max_completion_tokens: 2_000
)
```

Options are split into two groups:

1. **Managed cross-provider options**: normalized by `llm_gateway` and mapped to each provider API when supported.
2. **Provider-specific options**: passed through only when that provider/API pair explicitly allows them.

Unknown provider-specific options raise `ArgumentError` with the valid option list for that provider/API pair.

### Managed cross-provider options

| Option | Accepted values | What it means | Provider mapping notes |
|--------|-----------------|---------------|------------------------|
| `reasoning` | `"none"`, `"low"`, `"medium"`, `"high"`, `"xhigh"` | Request provider reasoning/thinking effort. | Anthropic maps to `thinking` token budgets. OpenAI Responses maps to `reasoning`. OpenAI Chat Completions maps to `reasoning_effort`. Groq maps to `reasoning_effort` and `reasoning_format: "parsed"`; Groq accepts `"default"`, `"low"`, `"medium"`, `"high"` and does not accept `"xhigh"`. |
| `cache_key` | String | Stable prompt/session cache key. | OpenAI Chat Completions and OpenAI Responses map this to `prompt_cache_key`. |
| `cache_retention` | `"short"`, `"long"`, `"none"` | Requested cache retention policy for `cache_key`. | OpenAI maps `"short"` to `"in_memory"`, `"long"` to `"24h"`, and `"none"` removes prompt-cache fields. If `cache_key` is set without retention, OpenAI defaults to `"short"`. |
| `max_completion_tokens` | Integer | Maximum generated tokens using gateway naming. | Anthropic maps to `max_tokens`; OpenAI Responses maps to `max_output_tokens`; OpenAI/Groq Chat Completions use `max_completion_tokens`. OpenAI Codex currently removes token limit parameters before sending. |
| `response_format` | String or Hash, provider-dependent | Requested final response shape, e.g. text or JSON. | OpenAI Chat Completions and Groq pass this as `response_format`; OpenAI Responses maps it under `text.format`; Anthropic maps JSON-ish formats to `output_config`. |

### Provider-specific options

Provider-specific options are maintained as explicit allowlists in the option mapper source. Use the mapper link to see the current allowed Ruby option keys and the provider documentation link for upstream meanings and values.

| Provider key | Provider/API pair | Option mapper source | Provider API documentation |
|--------------|-------------------|----------------------|----------------------------|
| `anthropic_messages` | Anthropic Messages Create | [`lib/llm_gateway/adapters/anthropic_option_mapper.rb`](lib/llm_gateway/adapters/anthropic_option_mapper.rb) | [Anthropic Messages API](https://platform.claude.com/docs/en/api/messages/create.md) |
| `openai_completions` | OpenAI Chat Completions Create | [`lib/llm_gateway/adapters/openai/chat_completions/option_mapper.rb`](lib/llm_gateway/adapters/openai/chat_completions/option_mapper.rb) | [OpenAI Chat Completions API](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create/index.md) |
| `openai_responses` | OpenAI Responses Create | [`lib/llm_gateway/adapters/openai/responses/option_mapper.rb`](lib/llm_gateway/adapters/openai/responses/option_mapper.rb) | [OpenAI Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create/index.md) |
| `openai_codex` | OpenAI Codex Responses-compatible endpoint | [`lib/llm_gateway/adapters/openai_codex/option_mapper.rb`](lib/llm_gateway/adapters/openai_codex/option_mapper.rb) | [OpenAI Responses API](https://developers.openai.com/api/reference/resources/responses/methods/create/index.md) |
| `groq_completions` | Groq Chat Completions Create | [`lib/llm_gateway/adapters/groq/option_mapper.rb`](lib/llm_gateway/adapters/groq/option_mapper.rb) | [Groq Chat API](https://console.groq.com/docs/api-reference.md#chat-create) |

Common provider-native options you may pass directly when allowed include OpenAI `prompt_cache_key` / `prompt_cache_retention` and Groq `reasoning_effort` / `reasoning_format`. Prefer the managed options above when you want portable behavior across providers.

## Quick Start: Streaming (all events)

```ruby
require "llm_gateway"
require "json"

# Build a provider adapter directly (not via prebuilt config)
adapter = LlmGateway.build_provider(
  provider: "openai_responses", # or anthropic_messages, groq_completions, ...
  api_key: ENV.fetch("OPENAI_API_KEY")
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

response = adapter.stream(transcript, tools: tools, model: "gpt-5.4", reasoning: "high") do |event|
  case event.type
  # AssistantStreamMessageEvent
  when :message_start
    puts "\n[message_start] #{event.delta.inspect}"
  when :message_delta
    puts "\n[message_delta] #{event.delta.inspect} usage=#{event.usage.inspect}"
  when :message_end
    puts "\n[message_end] final_id=#{event.message.id} stop_reason=#{event.message.stop_reason}"

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
    puts "\n[tool_start] id=#{event.id} name=#{event.name} type=#{event.tool_type} index=#{event.content_index}"
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
puts "timestamp: #{response.timestamp}" # Unix milliseconds
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
- `AssistantStreamMessageEvent`: `:message_start`, `:message_delta`
- `AssistantStreamMessageEndEvent`: `:message_end` with the final `event.message`
- `AssistantStreamEvent` (and subclasses):
  - Text: `:text_start`, `:text_delta`, `:text_end`
  - Tool call: `:tool_start`, `:tool_delta`, `:tool_end`
  - Tool result: `:tool_result_start`, `:tool_result_delta`, `:tool_result_end` (emitted by some provider-hosted/server tools)
  - Reasoning: `:reasoning_start`, `:reasoning_delta`, `:reasoning_end`

Non-final stream events expose `event.partial`, a `PartialAssistantMessage` snapshot accumulated so far. The final `:message_end` event exposes the complete `AssistantMessage` as `event.message` instead.

End events include helpers for the finalized current content block:
- `event.content` for `:text_end`, `:reasoning_end`, and `:tool_end`
- `event.text` for `:text_end`
- `event.reasoning` for `:reasoning_end`
- `event.tool_call` / `event.tool` for `:tool_end`

Usage counters are normalized as `:input`, `:cache_write`, `:cache_read`, `:output`, and `:total`. `:total` is the sum of all input-side buckets plus output. `usage[:raw]` contains the original provider usage/token payload.

### Stream API without handling events (final result only)

If you only care about the final `AssistantMessage`, call `stream` without a block:

```ruby
require "llm_gateway"

adapter = LlmGateway.build_provider(
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
)

result = adapter.stream("Write one short sentence about Ruby.", model: "gpt-5.4")

puts result.role         # "assistant"
puts result.timestamp    # Unix milliseconds
puts result.stop_reason  # "stop" (usually)
puts result.usage.inspect

text = result.content
  .select { |block| block.type == "text" }
  .map(&:text)
  .join

puts text
```

## Prompt classes

`LlmGateway::Prompt` wraps a reusable prompt, provider/model defaults, callbacks, optional tools, and prompt-cache options around the `stream` API.

```ruby
class AddTool < LlmGateway::Tool
  name "add"
  description "Adds two numbers"
  input_schema(type: "object")
  cache true # optional: mark the tool definition as cacheable where supported

  def execute(input)
    input[:left] + input[:right]
  end
end

class MathPrompt < LlmGateway::Prompt
  self.provider = LlmGateway.build_provider(
    provider: "openai_responses",
    api_key: ENV.fetch("OPENAI_API_KEY")
  )
  self.model = "gpt-5.4"

  TOOLS = [AddTool].freeze

  def prompt
    "What is 2 + 3? Use the add tool."
  end

  def system_prompt
    "You are a careful math assistant."
  end
end

response = MathPrompt.new(
  cache_key: "math-prompt-v1",
  cache_retention: "short"
).run

puts response.role # "assistant"
puts response.content.select { |block| block.type == "text" }.map(&:text).join
```

How `Prompt` works now:

- `prompt` is evaluated once per `run`.
- `run(provider:, model:, reasoning:, **options)` calls `stream` and returns the final normalized `AssistantMessage` after any tool calls complete.
- `stream(input = prompt, provider:, model:, reasoning:, **options, &block)` forwards to the provider and returns the normalized `AssistantMessage`.
- Tools are declared as tool classes in a `TOOLS` constant. `run` automatically executes returned `tool_use` blocks, appends `tool_result` messages, and loops until no tool calls remain.
- `system_prompt`, `tools`, `model`, `reasoning`, `cache_key`, and `cache_retention` are forwarded as stream options.
- `cache_retention` can also enable provider cache control for prompt-owned system/tool blocks where supported, and `Tool.cache true` marks a tool definition with `cache_control`.
- `before_execute` callbacks receive the resolved input. `after_execute` callbacks receive the final `AssistantMessage`.
- The old `extract_response` and `parse_response` hooks are no longer called; inspect, parse, or transform the returned `AssistantMessage` after `run`.

## Migration guides

- [0.7.0 migration guide](docs/migration_guide_0.7.0.md) — update `Prompt` subclasses for normalized `AssistantMessage` return values, automatic tool loops, `TOOLS`, and removed response hooks.
- [0.6.0 migration guide](docs/migration_guide_0.6.0.md) — move `model_key` to per-request `model:`, update provider keys, update `Prompt` usage, and migrate stream event/usage changes.
- [Migrating from `chat` to `stream`](docs/migration-guide.md) — use `stream` without a block when you only need the final response.

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
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
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
response = adapter.stream(transcript, tools: [weather_tool], model: "gpt-5.4")
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
  final_response = adapter.stream(transcript, tools: [weather_tool], model: "gpt-5.4")

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

### Server Tool Use

Some providers offer provider-hosted tools, such as OpenAI Responses code interpreter or Anthropic code execution. Pass these tools in the provider's native shape; `llm_gateway` preserves them and normalizes server tool activity in streams and final messages.

```ruby
openai_code_interpreter = {
  type: "code_interpreter",
  container: { type: "auto", memory_limit: "1g" }
}

anthropic_code_execution = {
  type: "code_execution_20250825",
  name: "code_execution"
}

tools = provider == "openai_responses" ? [openai_code_interpreter] : [anthropic_code_execution]
response = adapter.stream("Create a chart from this CSV and save it as PNG.", tools: tools) do |event|
  case event.type
  when :tool_start
    puts "server tool: #{event.name}" if event.tool_type == "server_tool_use"
  when :tool_delta
    print event.delta # streamed code/input JSON when the provider exposes it
  when :tool_result_start, :tool_result_delta
    print event.delta # provider-hosted result metadata/content when available
  end
end

response.content.each do |block|
  case block.type
  when "server_tool_use"
    puts "server tool #{block.name} input=#{block.input.inspect} id=#{block.id}"
  when "server_tool_result"
    puts "server tool result for #{block.tool_use_id}: #{block.content.inspect}"
  end
end
```

Cross-provider server tool handoffs are best-effort:

- Same provider/API replay keeps `server_tool_use` / `server_tool_result` blocks when possible.
- Cross-provider replay converts server tool uses into normal `tool_use` blocks and server tool results into `tool_result` blocks.
- `llm_gateway` does not translate server tool names between providers. Supply the target provider's server tool definition on the follow-up request.
- Some providers require the same server tool to be selected in `tools:` when replaying prior server tool activity.

## Agents

`LlmGateway::Agents::Harness` wraps the streaming API in a stateful conversation loop. It stores session history, executes `LlmGateway::Tool` classes automatically when the model emits tool calls, appends `tool_result` messages, repeats model turns until there are no more tool calls, supports queued user messages while a turn is running, and compacts older session context when needed.

```ruby
require "llm_gateway"
require "json"

class WeatherTool < LlmGateway::Tool
  name "get_weather"
  description "Get current weather for a location"
  input_schema(
    type: "object",
    properties: {
      location: { type: "string" }
    },
    required: ["location"]
  )

  def execute(input)
    location = input[:location] || input["location"]

    JSON.generate(
      location: location,
      temperature: 14,
      condition: "Cloudy"
    )
  end
end

class WeatherHarness < LlmGateway::Agents::Harness
  TOOLS = [WeatherTool]

  def system_prompt
    "You are a concise weather assistant. Use tools when useful."
  end
end

adapter = LlmGateway.build_provider(
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
)

session = LlmGateway::Agents::InMemorySessionManager.new("weather-session")
harness = WeatherHarness.new(
  session,
  provider: adapter,
  model: "gpt-5.4",
  reasoning: "high"
)

harness.prompt_message(
  role: "user",
  content: [ { type: "text", text: "What is the weather in London?" } ]
) do |event|
  case event.type
  when :agent_start
    puts "Agent started"
  when :turn_start
    puts "Turn started"
  when :message_update
    # Streaming provider events are wrapped on message update events.
    stream_event = event.stream_event
    print stream_event.delta if stream_event.respond_to?(:delta)
  when :tool_execution_start
    puts "\nExecuting #{event.parameters[:name]}"
  when :tool_execution_end
    puts "\nTool result: #{event.result.content}"
  when :agent_end
    puts "\nAgent finished"
  end
end

puts harness.transcript.inspect
```

Harness behavior:

- `prompt_message(message)` accepts an LLM-shaped message hash, records it in the session, streams the provider response, records the final assistant message, executes any returned tool calls from the harness class's `TOOLS` constant, records a user `tool_result` message, and continues until no tool calls remain.
- Harnesses pass `tools`, `system_prompt`, `model`, `reasoning`, `cache_key`, and `cache_retention` through the inherited `Prompt#stream` defaults.
- Pass `model:` and optional `reasoning:` to `new`, or set them later with `harness.model = "..."` / `harness.reasoning = "..."`. Model and reasoning changes are recorded as session events.
- `harness.transcript` (also aliased as `prompt`) returns the current model input: the latest compaction summary, if any, followed by active messages.
- `harness.run` continues from the current session state without adding a new user message. `harness.continue` requires an idle agent; it marks the agent busy, drains queued `:steer` messages and then queued `:follow_up` messages, runs, and marks the agent idle when finished. `prompt_message`/`steer_message`/`follow_up_message` enqueue the new user message; if the agent is idle, they then call `continue`, so existing queued messages in that queue stay ahead of the new message.

### Agent events

When a block is passed to `prompt_message`, `run`, or `continue`, the harness emits typed events:

- `:agent_start`
- `:turn_start`
- `:message_start`
- `:message_update` with `event.stream_event` containing the normalized streaming event from the provider
- `:message_end` with `event.message`
- `:tool_execution_start` with `event.parameters` (`id`, `type`, `name`, `input`)
- `:tool_execution_end` with `event.parameters` and `event.result`
- `:turn_end` with `event.message` and `event.tool_results`
- `:agent_end`

### Session managers and persistence

- `LlmGateway::Agents::InMemorySessionManager.new(session_id = nil)` keeps session events in memory for the lifetime of the process.
- `LlmGateway::Agents::FileSessionManager.new(file_name = nil, session_id: nil, session_start: nil, session_dir: nil)` persists session events as JSONL. If `file_name` is omitted, files are created under `LLM_GATEWAY_SESSION_DIR` or `~/.llm_gateway/sessions`.
- File sessions load existing JSONL sessions and append new events to the same file.
- Session event types include `session`, `message`, `model_change`, `reasoning_change`, and `compaction`. Queued messages are kept in memory and are persisted only when drained into the active conversation.

### Queues, steering, and follow-ups

Calls made while a harness is already processing are queued instead of recursively starting another run.

- `prompt_message(message)` queues to the harness's default queue while busy. The default is `:follow_up`.
- `steer_message(message)` and `follow_up_message(message)` enqueue to their matching queue. When idle, they also start `continue` after enqueueing.
- `:steer` messages are drained before the next model request in the current run.
- `:follow_up` messages run after the current turn finishes and after any tool-call loop has completed.
- Queued messages drain as `:all` by default. Set `harness.queue_drain_mode = :one_at_a_time` to drain one FIFO message at a time.
- Set `harness.default_queue_mode = :steer` or `:follow_up` to change where busy `prompt_message` calls are queued.

### Compaction

Before starting a new user message and before draining queued follow-up work, the harness checks whether compaction is needed. It compacts when either:

- the latest recorded message usage exceeds `LlmGateway::Agents::Harness::COMPACTION_TOKEN_THRESHOLD`, or
- the latest assistant message is older than `LlmGateway::Agents::Harness::COMPACTION_IDLE_THRESHOLD_SECONDS`.

Compaction calls `adapter.stream(active_messages, system: "Summarize the conversation so far for future context.", tools: [])`, stores the returned assistant message as a `compaction` event, and builds future model input as the compaction summary plus messages recorded after that compaction.

### Built-in agent tools

The agent harness can use any `LlmGateway::Tool` subclass in its `TOOLS` constant. The library also provides optional coding-oriented tools. Require the ones you want and include them in your harness:

```ruby
require "llm_gateway/agents/tools/read_tool"
require "llm_gateway/agents/tools/bash_tool"
require "llm_gateway/agents/tools/edit_tool"
require "llm_gateway/agents/tools/write_tool"

class CodingHarness < LlmGateway::Agents::Harness
  TOOLS = [ReadTool, BashTool, EditTool, WriteTool]
end
```

- `ReadTool` (`read`) reads text files and supported images (`jpg`, `png`, `gif`, `webp`). Text output is truncated to 2,000 lines or 50KB from the start; use `offset`/`limit` to continue through large files.
- `BashTool` (`bash`) runs a command in the current working directory, combines stdout/stderr, supports an optional timeout, truncates long output to the last 2,000 lines or 50KB, and saves full truncated output to a temp file.
- `EditTool` (`edit`) edits one file with one or more exact `edits[].oldText` → `edits[].newText` replacements. Each `oldText` must be unique in the original file and edits must not overlap.
- `WriteTool` (`write`) creates parent directories as needed and writes or overwrites a file.

## Image Input

Send images by including an `image` content block in a user message.

```ruby
require "llm_gateway"
require "base64"

adapter = LlmGateway.build_provider(
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
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

result = adapter.stream(message, model: "gpt-5.4") # stream API, no event block

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
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
)

result = adapter.stream(
  "Think step by step and then compute 482 * 17.",
  model: "gpt-5.4",
  reasoning: "high"
)

puts "stop_reason: #{result.stop_reason}"
puts "usage: #{result.usage.inspect}" # normalized keys: :input, :cache_write, :cache_read, :output, :total, :raw

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

result = adapter.stream("Solve 99 * 99 with brief reasoning.", model: "gpt-5.4", reasoning: "high") do |event|
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
  - keys are `:input`, `:cache_write`, `:cache_read`, `:output`, `:total`, and `:raw`

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
   - Final output is accumulated into a normalized `AssistantMessage` (`id`, `model`, `timestamp` as Unix milliseconds, `usage`, `stop_reason`, `content`, etc.).

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
  provider: "openai_responses",
  api_key: ENV.fetch("OPENAI_API_KEY")
)
# Build context (transcript)
transcript = [
  { role: "user", content: "Plan a 3-day trip to Tokyo." }
]

# Run one turn and persist assistant output
first = adapter.stream(transcript, model: "gpt-5.4")
transcript << first.to_h

# Serialize (store in DB/file/cache)
json_context = JSON.generate(transcript)

# ...later / elsewhere...
restored_transcript = JSON.parse(json_context)

# Continue conversation from restored context
restored_transcript << { role: "user", content: "Now make it budget-friendly." }
second = adapter.stream(restored_transcript, model: "gpt-5.4")

puts second.content.select { |b| b.type == "text" }.map(&:text).join
```

What to persist:
- full transcript array (including assistant messages from `response.to_h`)
- any tool result messages you appended
- optional app metadata (user id, conversation id, timestamps) alongside the transcript

Tip: if you serialize to JSON, keys become strings on parse; `llm_gateway` accepts standard hash input and normalizes internally.

### Message metadata

Input messages may include app-owned metadata, for example a `details` hash used for trace IDs, database IDs, UI state, or other per-message decorations:

```ruby
transcript = [
  {
    role: "user",
    content: "Hello",
    details: { trace_id: "msg-123", ui_thread_id: "thread-456" }
  }
]

adapter.stream(transcript, model: "gpt-5.4")
```

`llm_gateway` preserves this as part of your local transcript shape, but strips `details` before sending user or assistant messages to provider APIs. This lets applications keep message metadata next to the message without leaking unsupported fields to OpenAI, Anthropic, Groq, or Codex request payloads.

## OAuth

Use OAuth-capable providers (for example `openai_codex` and `anthropic_messages`) by supplying an `access_token` when building the adapter.

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
  access_token: current_access_token
)

result = adapter.stream("Hello from OAuth auth", model: "gpt-5.4")
puts result.content.select { |b| b.type == "text" }.map(&:text).join
```

If your app refreshes tokens in the background, rebuild the adapter (or recreate client state) with the newest `access_token` before subsequent calls.

### Codex rate-limit reset metadata

OpenAI Codex usage-limit responses include reset information on `LlmGateway::Errors::RateLimitError`:

```ruby
begin
  adapter.stream("Hello from OAuth auth", model: "gpt-5.4")
rescue LlmGateway::Errors::RateLimitError => e
  puts e.message                 # "The usage limit has been reached"
  puts e.reset_after_seconds     # primary reset window, when available
  puts e.reset_at                # Time for the primary reset, when available
  puts e.rate_limit_info.inspect # full parsed Codex headers/body metadata
end
```

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

For OAuth-backed providers (`anthropic_messages`, `openai_codex`), the live test helper only loads real OAuth credentials while the cassette is being recorded. Once the cassette exists, replay uses placeholder tokens/account IDs so the test suite can run without local OAuth state. API-key providers still require the relevant API key when recording. Sensitive authorization headers and selected response headers are redacted before cassettes are written.

Some tests pass `redact_request_body: true` to `with_vcr_adapter`; those cassettes match on method and URI only and replace large request bodies with `"<huge prompt body redacted>"`.
