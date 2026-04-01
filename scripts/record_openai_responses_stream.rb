#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../lib/llm_gateway"

# Fill these in manually before running.
API_KEY = ENV["OPENAI_API_KEY"]
DEFAULT_MODEL_KEY = "gpt-5.4"
REASONING_MODEL_KEY = DEFAULT_MODEL_KEY

OUTPUT_DIR = File.expand_path("../test/fixtures/openai_responses_stream", __dir__)

TEXT_MESSAGES = [
  {
    role: "user",
    content: "Reply with exactly: Hello test successful"
  }
].freeze

TOOL_MESSAGES = [
  {
    role: "user",
    content: "Calculate 15 + 27 using the math_operation tool"
  }
].freeze

REASONING_MESSAGES = [
  {
    role: "user",
    content: "Think step by step about 44 + 27, then answer clearly."
  }
].freeze

TOOLS = [
  {
    name: "math_operation",
    description: "Perform a basic math operation on two numbers",
    input_schema: {
      type: "object",
      properties: {
        a: { type: "number", description: "The first number" },
        b: { type: "number", description: "The second number" },
        operation: {
          type: "string",
          enum: [ "add", "subtract", "multiply", "divide" ],
          description: "The operation to perform"
        }
      },
      required: [ "a", "b", "operation" ]
    }
  }
].freeze

SYSTEM = [].freeze

if API_KEY.empty? || DEFAULT_MODEL_KEY.empty?
  warn "Please set OPENAI_API_KEY and edit scripts/record_openai_responses_stream.rb if needed before running."
  exit 1
end

FileUtils.mkdir_p(OUTPUT_DIR)

def build_responses_body(messages:, system: [], tools: nil)
  LlmGateway::Adapters::OpenAi::Responses::InputMapper.map(
    messages: messages,
    response_format: { type: "text" },
    tools: tools,
    system: system
  )
end

def record_stream(path:, model_key:, api_key:, messages:, system: [], tools: nil, reasoning: nil)
  client = LlmGateway::Clients::OpenAi.new(
    model_key: model_key,
    api_key: api_key
  )

  mapped = build_responses_body(
    messages: messages,
    system: system,
    tools: tools
  )

  chunks = []

  client.stream_responses(
    mapped[:messages],
    system: mapped[:system],
    tools: mapped[:tools],
    reasoning: reasoning
  ) do |chunk|
    chunks << chunk
  end

  File.write(path, JSON.pretty_generate(chunks) + "\n")
  puts "Wrote #{chunks.length} chunks to #{path}"
end

record_stream(
  path: File.join(OUTPUT_DIR, "text_events.json"),
  model_key: DEFAULT_MODEL_KEY,
  api_key: API_KEY,
  messages: TEXT_MESSAGES,
  system: SYSTEM
)

record_stream(
  path: File.join(OUTPUT_DIR, "tool_events.json"),
  model_key: DEFAULT_MODEL_KEY,
  api_key: API_KEY,
  messages: TOOL_MESSAGES,
  system: SYSTEM,
  tools: TOOLS
)

record_stream(
  path: File.join(OUTPUT_DIR, "reasoning_events.json"),
  model_key: REASONING_MODEL_KEY,
  api_key: API_KEY,
  messages: REASONING_MESSAGES,
  system: SYSTEM,
  reasoning: { effort: "high", summary: 'detailed'  }
)
