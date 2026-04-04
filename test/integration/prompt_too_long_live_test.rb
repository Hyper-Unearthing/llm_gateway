# frozen_string_literal: true

require "test_helper"
require "json"
require "time"
require "fileutils"

class PromptTooLongLiveTest < Test
  def teardown
    LlmGateway.reset_configuration!
  end

  def load_provider(provider:, model:)
    config = {
      "provider" => provider,
      "model_key" => model
    }

    case provider
    when "openai_apikey_completions", "openai_apikey_responses"
      api_key = ENV["OPENAI_API_KEY"].to_s
      skip("Skipped: missing OPENAI_API_KEY") if api_key.empty?
      config["api_key"] = api_key
    when "anthropic_apikey_messages"
      api_key = ENV["ANTHROPIC_API_KEY"].to_s
      skip("Skipped: missing ANTHROPIC_API_KEY") if api_key.empty?
      config["api_key"] = api_key
    when "anthropic_oauth_messages"
      config["provider"] = "anthropic_apikey_messages"
      config["api_key"] = oauth_access_token_for("anthropic")
    when "openai_oauth_codex"
      creds = load_auth_credentials("openai")
      config["api_key"] = oauth_access_token_for("openai")
      config["account_id"] = creds["account_id"] if creds["account_id"]
    end

    LlmGateway.build_provider(config)
  end

  def auth_file_path
    File.expand_path(ENV.fetch("LLM_GATEWAY_AUTH_FILE", "~/.config/llm_gateway/auth.json"))
  end

  def load_auth_credentials(provider)
    path = auth_file_path
    skip("Skipped: missing auth file at #{path}") unless File.exist?(path)

    auth = JSON.parse(File.read(path))
    creds = auth[provider]
    skip("Skipped: missing #{provider} credentials in #{path}") unless creds

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
    when "anthropic"
      token = LlmGateway::Clients::Claude.new.get_oauth_access_token(
        access_token: creds["access_token"],
        refresh_token: creds["refresh_token"],
        expires_at: creds["expires_at"]
      ) do |access_token, refresh_token, expires_at|
        persist_auth_credentials("anthropic", {
          "access_token" => access_token,
          "refresh_token" => refresh_token,
          "expires_at" => expires_at&.iso8601
        })
      end

      persist_auth_credentials("anthropic", { "access_token" => token }) if token != creds["access_token"]
      token
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

  def huge_prompt
    "Please reply with one short sentence.\n\n" + ("lorem ipsum dolor sit amet " * 240_000)
  end

  def assert_prompt_too_long(adapter, name, provider)
    error = assert_raises(LlmGateway::Errors::PromptTooLong) do
      adapter.stream(huge_prompt)
    end

    assert LlmGateway::Errors.context_overflow_message?(error.message),
      "Expected prompt-length related error message for #{provider}, got: #{error.message}"
  end

  def self.define_prompt_too_long_debug_test(name:, provider:, model:)
    test "#{name} prompt too long debug" do
      without_vcr do
        adapter = load_provider(provider:, model:)
        assert_prompt_too_long(adapter, name, provider)
      end
    end
  end

  define_prompt_too_long_debug_test(
    name: "openai_apikey_completions_gpt_5_1",
    provider: "openai_apikey_completions",
    model: "gpt-5.1"
  )

  define_prompt_too_long_debug_test(
    name: "anthropic_apikey_messages_claude_sonnet_4",
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_prompt_too_long_debug_test(
    name: "openai_apikey_responses_gpt_5_4",
    provider: "openai_apikey_responses",
    model: "gpt-5.4"
  )

  define_prompt_too_long_debug_test(
    name: "anthropic_oauth_messages_claude_sonnet_4",
    provider: "anthropic_oauth_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_prompt_too_long_debug_test(
    name: "openai_oauth_codex_gpt_5_4",
    provider: "openai_oauth_codex",
    model: "gpt-5.4"
  )
end
