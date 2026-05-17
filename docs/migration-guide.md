# Dont use LlmGateway::Client 

use the provider pattern instead 
# Migrating from `chat` to `stream`

The `chat` method will be deprecated. New code should use `stream`.

If your application only needs the final assistant response, call `stream` without a block. You do not need to handle streaming events.

## Basic migration

### Before

```ruby
result = adapter.chat("Write one short sentence about Ruby.")
```

### After

```ruby
result = adapter.stream("Write one short sentence about Ruby.")
```

`stream` returns the final assembled `AssistantMessage`, so most response-handling code can stay the same.

## Migrating calls with options

Pass the same options to `stream` that you passed to `chat`.

### Before

```ruby
result = adapter.chat(
  transcript,
  tools: tools,
  system: "You are a helpful assistant.",
  reasoning: "high"
)
```

### After

```ruby
result = adapter.stream(
  transcript,
  tools: tools,
  system: "You are a helpful assistant.",
  reasoning: "high"
)
```

## Reading the final response

The returned object has the same final assistant message shape your existing `chat` code expects:

```ruby
result = adapter.stream(transcript)

puts result.role
puts result.stop_reason
puts result.usage.inspect

text = result.content
  .select { |block| block.type == "text" }
  .map(&:text)
  .join

puts text
```

## Tool-call flows

If your existing `chat` flow inspected the final response for tool calls, keep the same pattern after switching to `stream`:

```ruby
response = adapter.stream(transcript, tools: [weather_tool])

tool_uses = response.content.select { |block| block.type == "tool_use" }

# Execute tools, append tool_result messages to the transcript,
# then call stream again for the next assistant response.
```

## Recommended migration steps

1. Replace `adapter.chat(...)` with `adapter.stream(...)`.
2. Do not pass a block if you only need the final response.
3. Run tests that verify text extraction, tool-call detection, stop reasons, and usage accounting.
4. Remove new uses of `chat` from application code before deprecation.

# Update ClassNames

If you are using any of these classes you should use the new names

## Clients

- LlmGateway::Clients::Claude → LlmGateway::Clients::Anthropic
- LlmGateway::Clients::OpenAi → LlmGateway::Clients::OpenAI

## Adapters: Anthropic side

- LlmGateway::Adapters::Claude::* → LlmGateway::Adapters::Anthropic::*
    - Client
    - MessagesAdapter
    - InputMapper
    - OutputMapper
    - StreamMapper
    - BidirectionalMessageMapper
    - FileOutputMapper

## Adapters: OpenAI side

- LlmGateway::Adapters::OpenAi::* → LlmGateway::Adapters::OpenAI::*
    - Client
    - ChatCompletionsAdapter
    - ResponsesAdapter
    - PromptCacheOptionMapper
    - FileOutputMapper
    - ChatCompletions
    - Responses

## Adapters: Groq side

Groq now reuses the OpenAI Chat Completions mapper stack via `ActsLikeOpenAIChatCompletions`.
The dedicated Groq mapper classes were removed rather than aliased:

- LlmGateway::Adapters::Groq::InputMapper → LlmGateway::Adapters::OpenAI::ChatCompletions::InputMapper
- LlmGateway::Adapters::Groq::OutputMapper → LlmGateway::Adapters::OpenAI::ChatCompletions::OutputMapper
- LlmGateway::Adapters::Groq::BidirectionalMessageMapper → LlmGateway::Adapters::OpenAI::ChatCompletions::BidirectionalMessageMapper

Still provider-specific:

- LlmGateway::Clients::Groq
- LlmGateway::Adapters::Groq::ChatCompletionsAdapter
- LlmGateway::Adapters::Groq::OptionMapper
