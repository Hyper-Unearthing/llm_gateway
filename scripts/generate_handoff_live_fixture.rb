# frozen_string_literal: true

require "json"
require "time"
require "fileutils"
require 'debug'
require_relative "../lib/llm_gateway"
require_relative "../test/utils/calculator_tool_helper"

class HandoffLiveFixtureGenerator
  include CalculatorToolHelper

  PAIRS = [
    { provider: "openai_apikey_completions", model: "gpt-5.1" },
    { provider: "openai_apikey_responses", model: "gpt-5.4" },
    { provider: "openai_oauth_codex", model: "gpt-5.4" },
    { provider: "anthropic_apikey_messages", model: "claude-sonnet-4-20250514" }
  ].freeze

  FIXTURE_PATH = File.expand_path("../test/fixtures/handoff_live_fixture.json", __dir__)

  def run
    flat_transcript = []
    skipped = []

    PAIRS.each do |pair|
      begin
        adapter = load_provider(provider: pair[:provider], model: pair[:model])
        mini_context = generate_mini_context(adapter)
        flat_transcript.concat(mini_context.map(&:to_h))
        puts "[ok] #{pair[:provider]} / #{pair[:model]}"
      rescue StandardError => e
        skipped << pair.merge(error: e.message)
        puts "[skip] #{pair[:provider]} / #{pair[:model]} -> #{e.message}"
      ensure
        LlmGateway.reset_configuration!
      end
    end

    FileUtils.mkdir_p(File.dirname(FIXTURE_PATH))
    File.write(FIXTURE_PATH, JSON.pretty_generate(flat_transcript) + "\n")

    puts "\nWrote fixture: #{FIXTURE_PATH}"
    puts "Messages: #{flat_transcript.length}"
    puts "Skipped pairs: #{skipped.length}"
  end

  private

  def generate_mini_context(adapter)
    transcript = [
      {
        role: "user",
        content: "Think hard about this, then use the math_operation tool to double 21 by multiplying 21 and 2. Call the tool."
      }
    ]

    first = adapter.stream(transcript, tools: [ math_operation_tool ], reasoning: "high")
    raise first.error_message if first.stop_reason == "error"

    transcript << first

    tool_call = first.content.find { |block| block.type == "tool_use" && block.name == "math_operation" }
    raise "model did not call math_operation" unless tool_call

    tool_result = {
      role: "developer",
      content: [
        {
          type: "tool_result",
          tool_use_id: tool_call.id,
          content: evaluate_math_operation(tool_call.input).to_s
        }
      ]
    }
    transcript << tool_result

    second = adapter.stream(
      transcript.map { |m| m.respond_to?(:to_h) ? m.to_h : m },
      tools: [ math_operation_tool ],
      reasoning: "high"
    )
    raise second.error_message if second.stop_reason == "error"

    transcript << second
    transcript
  end

  def load_provider(provider:, model:)
    config = {
      "provider" => provider,
      "model_key" => model
    }

    case provider
    when "openai_apikey_completions", "openai_apikey_responses"
      api_key = ENV["OPENAI_API_KEY"].to_s
      raise "missing OPENAI_API_KEY" if api_key.empty?

      config["api_key"] = api_key
    when "anthropic_apikey_messages"
      api_key = ENV["ANTHROPIC_API_KEY"].to_s
      raise "missing ANTHROPIC_API_KEY" if api_key.empty?

      config["api_key"] = api_key
    when "openai_oauth_codex"
      creds = load_auth_credentials("openai")
      config["api_key"] = oauth_access_token_for("openai")
      config["account_id"] = creds["account_id"] if creds["account_id"]
    else
      raise ArgumentError, "Unsupported provider: #{provider}"
    end

    LlmGateway.build_provider(config)
  end

  def auth_file_path
    File.expand_path(ENV.fetch("LLM_GATEWAY_AUTH_FILE", "~/.config/llm_gateway/auth.json"))
  end

  def load_auth_credentials(provider)
    path = auth_file_path
    raise "missing auth file at #{path}" unless File.exist?(path)

    auth = JSON.parse(File.read(path))
    creds = auth[provider]
    raise "missing #{provider} credentials in #{path}" unless creds

    creds
  end

  def persist_auth_credentials(provider, attributes)
    path = auth_file_path
    FileUtils.mkdir_p(File.dirname(path))

    auth = File.exist?(path) ? JSON.parse(File.read(path)) : {}
    auth[provider] ||= {}
    auth[provider].merge!(attributes)

    File.write(path, JSON.pretty_generate(auth) + "\n")
  end

  def oauth_access_token_for(provider)
    creds = load_auth_credentials(provider)

    case provider
    when "openai"
      token = LlmGateway::Clients::OpenAi.new.get_oauth_access_token(
        access_token: creds["access_token"],
        refresh_token: creds["refresh_token"],
        expires_at: creds["expires_at"],
        account_id: creds["account_id"]
      ) do |access_token, refresh_token, expires_at|
        persist_auth_credentials("openai", {
          "access_token" => access_token,
          "refresh_token" => refresh_token,
          "expires_at" => expires_at&.iso8601
        })
      end

      persist_auth_credentials("openai", { "access_token" => token }) if token != creds["access_token"]
      token
    else
      raise ArgumentError, "Unsupported OAuth provider: #{provider}"
    end
  end
end

HandoffLiveFixtureGenerator.new.run
