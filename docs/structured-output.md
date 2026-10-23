# Structured final output

Pass a JSON Schema through `response_format` when the selected provider/model supports structured output:

```ruby
adapter.stream(messages, model: model, tools: tools, response_format: {
  type: "json_schema",
  json_schema: {
    name: "repair_result",
    strict: true,
    schema: {
      type: "object",
      additionalProperties: false,
      properties: {
        outcome: { type: "string", enum: ["resolved", "needs_human"] },
        message: { type: "string" }
      },
      required: ["outcome", "message"]
    }
  }
})
```

OpenAI Chat Completions and Groq receive this envelope directly. OpenAI Responses (including Codex) receives the definition under `text.format`; Anthropic receives the schema under `output_config.format`, preserving native output settings and reasoning effort. Symbol and JSON string keys are supported. Provider-native options remain available.

Anthropic does not support schema-less `json_object` mode: use an explicit schema. Older gateway versions incorrectly discarded the supplied schema and emitted an invalid `output_config.format` string.

This changes request translation, not response parsing or agent completion semantics. Tool-call turns remain ordinary tool calls; validate the final text against the application's result contract. A refusal, interruption, missing final message, or invalid JSON is not a successful structured result. Provider/model support for schemas alongside tools varies and is ultimately enforced by the provider.
