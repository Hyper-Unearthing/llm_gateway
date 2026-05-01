#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require_relative "../lib/llm_gateway"

API_KEY = ENV["OPENAI_API_KEY"]
MODEL_KEY = "gpt-5.4"
OUTPUT_PATH = File.expand_path("../test/fixtures/openai_responses_stream/code_generation_tool_events.json", __dir__)

CSV_DATA = <<~CSV.freeze
  Month,Average Temperature (°C),Deviation from 1991-2020 Norm (°C)
  January,0.0,+1.5
  February,1.3,+1.7
  March,4.1,+1.5
  April,8.2,+1.9
  May,10.3,-0.2
  June,17.6,+3.8
  July,15.4,-0.3
  August,16.4,+1.2
  September,11.9,+0.5
  October,7.2,-0.2
  November,2.3,+0.1
  December,1.3,+2.0
  Annual Mean,8.0,+1.1
CSV

PROMPT = <<~PROMPT.freeze
  Use the python tool to read this CSV and create a PNG line chart.
  Requirements:
  - Plot monthly average temperature (Jan-Dec only; ignore Annual Mean)
  - Include x/y axes and month labels
  - Save the chart as a PNG file

  CSV:
  #{CSV_DATA}
PROMPT

TOOLS = [
  {
    type: "code_interpreter",
    container: { type: "auto", memory_limit: "1g" }
  }
].freeze

if API_KEY.to_s.empty? || MODEL_KEY.to_s.empty?
  warn "Please set OPENAI_API_KEY before running this script."
  exit 1
end

FileUtils.mkdir_p(File.dirname(OUTPUT_PATH))

client = LlmGateway::Clients::OpenAi.new(
  model_key: MODEL_KEY,
  api_key: API_KEY
)

mapped = LlmGateway::Adapters::OpenAi::Responses::InputMapper.map(
  messages: [ { role: "user", content: PROMPT } ],
  response_format: { type: "text" },
  tools: TOOLS,
  system: []
)

chunks = []

client.stream_responses(
  mapped[:messages],
  system: mapped[:system],
  tools: mapped[:tools]
) do |chunk|
  chunks << chunk
end

File.write(OUTPUT_PATH, JSON.pretty_generate(chunks) + "\n")
puts "Wrote #{chunks.length} chunks to #{OUTPUT_PATH}"
