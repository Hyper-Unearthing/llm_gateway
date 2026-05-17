# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module LiveTestHelper
  def load_provider(provider:, model:, replaying_vcr: false)
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
      config["api_key"] = replaying_vcr ? "sk-ant-oat-vcr-replay-token" : oauth_access_token_for("anthropic")
    when "openai_oauth_codex"
      if replaying_vcr
        config["api_key"] = "vcr-replay-token"
        config["account_id"] = "vcr-replay-account"
      else
        creds = load_auth_credentials("openai")
        config["api_key"] = oauth_access_token_for("openai")
        config["account_id"] = creds["account_id"] if creds["account_id"]
      end
    end

    LlmGateway.build_provider(config)
  end

  def skip_on_authentication_error
    yield
  rescue LlmGateway::Errors::AuthenticationError => e
    skip("Skipped due to authentication error: #{e.message}")
  end

  def with_vcr_adapter(provider:, model:, redact_request_body: false)
    cassette_name = vcr_cassette_name
    match_requests_on = redact_request_body ? %i[method uri] : %i[method uri json_body]
    replaying_vcr = oauth_provider?(provider) && File.exist?(vcr_cassette_path(cassette_name))

    cassette_options = { match_requests_on: match_requests_on }
    cassette_options[:tag] = :redact_large_request_body if redact_request_body

    VCR.use_cassette(cassette_name, cassette_options) do
      skip_on_authentication_error do
        yield load_provider(provider: provider, model: model, replaying_vcr: replaying_vcr)
      end
    end
  end

  def oauth_provider?(provider)
    %w[anthropic_oauth_messages openai_oauth_codex].include?(provider)
  end

  def vcr_cassette_path(cassette_name)
    direct_path = File.join(VCR.configuration.cassette_library_dir, "#{cassette_name}.yml")
    return direct_path if File.exist?(direct_path)

    # VCR sanitizes path segments like `stream_test.rb` to `stream_test_rb`.
    File.join(VCR.configuration.cassette_library_dir, "#{cassette_name.tr('.', '_')}.yml")
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
      token = LlmGateway::Clients::Anthropic.new.get_oauth_access_token(
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
      token = LlmGateway::Clients::OpenAI.new.get_oauth_access_token(
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
