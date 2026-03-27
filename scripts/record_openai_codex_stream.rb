#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require_relative "../lib/llm_gateway"

# Credentials from environment variables (use scripts/create_openai_codex_credentials.rb to obtain).
ACCOUNT_ID     = ENV["OPENAI_CODEX_ACCOUNT_ID"]
ACCESS_TOKEN   = ENV["OPENAI_CODEX_ACCESS_TOKEN"]
REFRESH_TOKEN  = ENV["OPENAI_CODEX_REFRESH_TOKEN"]
EXPIRES_AT_RAW = ENV["OPENAI_CODEX_EXPIRES_AT"]

DEFAULT_MODEL_KEY   = "gpt-5.4"
REASONING_MODEL_KEY = DEFAULT_MODEL_KEY

OUTPUT_DIR = File.expand_path("../test/fixtures/openai_codex_stream", __dir__)

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
        a: { type: "number",  description: "The first number" },
        b: { type: "number",  description: "The second number" },
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

if ACCESS_TOKEN.to_s.empty? && REFRESH_TOKEN.to_s.empty?
  warn "Please set OPENAI_CODEX_ACCESS_TOKEN (and optionally OPENAI_CODEX_REFRESH_TOKEN) before running."
  warn "Run scripts/create_openai_codex_credentials.rb to obtain credentials."
  exit 1
end

FileUtils.mkdir_p(OUTPUT_DIR)

def parse_expires_at(raw)
  return nil if raw.to_s.empty?

  Time.parse(raw)
rescue ArgumentError
  warn "Warning: could not parse OPENAI_CODEX_EXPIRES_AT value #{raw.inspect}, treating as nil."
  nil
end

def build_codex_body(messages:, system: [], tools: nil)
  LlmGateway::Adapters::OpenAiCodex::InputMapper.map(
    messages: messages,
    response_format: { type: "text" },
    tools: tools,
    system: system
  )
end

def record_stream(path:, model_key:, messages:, system: [], tools: nil, reasoning_effort: nil)
  expires_at = parse_expires_at(EXPIRES_AT_RAW)

  client = LlmGateway::Clients::OpenAiCodex.new(
    model_key: model_key,
    access_token: ACCESS_TOKEN,
    refresh_token: REFRESH_TOKEN,
    expires_at: expires_at,
    account_id: ACCOUNT_ID,
    reasoning_effort: reasoning_effort
  )

  # Persist refreshed tokens back to the environment so subsequent calls
  # within this script benefit from a fresh token if one was obtained.
  client.on_token_refresh = lambda do |new_access, new_refresh, new_expires|
    ENV["OPENAI_CODEX_ACCESS_TOKEN"] = new_access
    ENV["OPENAI_CODEX_REFRESH_TOKEN"] = new_refresh
    ENV["OPENAI_CODEX_EXPIRES_AT"]    = new_expires&.iso8601.to_s
    puts "  [token refreshed]"
  end

  mapped = build_codex_body(
    messages: messages,
    system: system,
    tools: tools
  )

  chunks = []

  client.stream(
    mapped[:messages],
    system: mapped[:system],
    tools: mapped[:tools]
  ) do |chunk|
    chunks << chunk
  end

  File.write(path, JSON.pretty_generate(chunks) + "\n")
  puts "Wrote #{chunks.length} chunks to #{path}"
end

record_stream(
  path: File.join(OUTPUT_DIR, "text_events.json"),
  model_key: DEFAULT_MODEL_KEY,
  messages: TEXT_MESSAGES,
  system: SYSTEM
)

record_stream(
  path: File.join(OUTPUT_DIR, "tool_events.json"),
  model_key: DEFAULT_MODEL_KEY,
  messages: TOOL_MESSAGES,
  system: SYSTEM,
  tools: TOOLS
)

record_stream(
  path: File.join(OUTPUT_DIR, "reasoning_events.json"),
  model_key: REASONING_MODEL_KEY,
  messages: REASONING_MESSAGES,
  system: SYSTEM,
  reasoning_effort: "high"
)
