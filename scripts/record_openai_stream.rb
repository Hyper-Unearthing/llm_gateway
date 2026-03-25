#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../lib/llm_gateway"

# Fill these in manually before running.
API_KEY = ENV["OPENAI_API_KEY"]
DEFAULT_MODEL_KEY = "gpt-5.4"
REASONING_MODEL_KEY = DEFAULT_MODEL_KEY

OUTPUT_DIR = File.expand_path("../test/fixtures/openai_stream", __dir__)

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
    type: "function",
    function: {
      name: "math_operation",
      description: "Perform a basic math operation on two numbers",
      parameters: {
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
  }
].freeze

SYSTEM = [].freeze

if API_KEY.empty? || DEFAULT_MODEL_KEY.empty?
  warn "Please edit scripts/record_openai_stream.rb and set API_KEY and DEFAULT_MODEL_KEY first."
  exit 1
end

FileUtils.mkdir_p(OUTPUT_DIR)

def record_stream(path:, model_key:, api_key:, messages:, system: [], tools: nil, reasoning_effort: nil)
  client = LlmGateway::Clients::OpenAi.new(
    model_key: model_key,
    api_key: api_key
  )

  chunks = []

  client.stream(
    messages,
    system: system,
    tools: tools,
    reasoning_effort: reasoning_effort
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
  reasoning_effort: "medium"
)
