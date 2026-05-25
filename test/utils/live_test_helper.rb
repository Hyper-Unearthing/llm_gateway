# frozen_string_literal: true

require "json"
require "time"
require "fileutils"

module LiveTestHelper
  ModelBoundAdapter = Struct.new(:adapter, :model) do
    def chat(message, tools: nil, system: nil, **options)
      adapter.chat(message, tools: tools, system: system, model: model, **options)
    end

    def stream(message, tools: nil, system: nil, **options, &block)
      adapter.stream(message, tools: tools, system: system, model: model, **options, &block)
    end

    def method_missing(name, *args, **kwargs, &block)
      if adapter.respond_to?(name)
        adapter.public_send(name, *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      adapter.respond_to?(name, include_private) || super
    end
  end

  def load_provider(provider:, model:, replaying_vcr: false, oauth:)
    config = {
      "provider" => provider
    }
    if provider == "openai_codex"
      config["api_key"] = replaying_vcr ? "vcr-replay-token" : oauth_access_token_for("openai")
      config["account_id"] = replaying_vcr ? "vcr-replay-account" : load_auth_credentials("openai")["account_id"]
    elsif oauth == true
      if provider == "anthropic_messages"
        config["api_key"] = replaying_vcr ? "sk-ant-oat-vcr-replay-token" : oauth_access_token_for("anthropic")
      end
    elsif replaying_vcr
      config["api_key"] = "vcr-replay-token"
    end

    ModelBoundAdapter.new(LlmGateway.build_provider(config), model)
  end

  def with_vcr_adapter(provider:, model:, redact_request_body: false, oauth: false)
    cassette_name = vcr_cassette_name
    match_requests_on = redact_request_body ? %i[method uri] : %i[method uri json_body]
    replaying_vcr = File.exist?(vcr_cassette_path(cassette_name))

    cassette_options = { match_requests_on: match_requests_on }
    cassette_options[:tag] = :redact_large_request_body if redact_request_body

    VCR.use_cassette(cassette_name, cassette_options) do
      yield load_provider(provider: provider, model: model, replaying_vcr: replaying_vcr, oauth:,)
    end
  end

  def assert_stream_message_end_matches_response(message_end_event, response)
    refute_nil message_end_event, "message_end event occurred"
    assert_instance_of AssistantMessage, message_end_event.message
    assert_same response, message_end_event.message
    assert_equal response.to_h, message_end_event.message.to_h
    refute_empty message_end_event.message.provider
    refute_empty message_end_event.message.api
  end

  def record_live_handoff_result(test_file:, provider:, model:, result:)
    fixture_dir = File.expand_path("../fixtures/handoff/#{File.basename(test_file, ".rb")}", __dir__)
    FileUtils.mkdir_p(fixture_dir)

    pair_name = "#{provider}_#{model}".gsub(/[^A-Za-z0-9_.-]+/, "_")
    path = File.join(fixture_dir, "#{pair_name}.json")
    payload = File.exist?(path) ? JSON.parse(File.read(path)) : {}
    payload[name.sub(/^test_/, "")] = jsonable_live_result(result)

    File.write(path, JSON.pretty_generate(payload) + "\n")
  end

  def jsonable_live_result(value)
    case value
    when Array
      value.map { |item| jsonable_live_result(item) }
    when Hash
      value.each_with_object({}) { |(key, item), acc| acc[key.to_s] = jsonable_live_result(item) }
    else
      value.respond_to?(:to_h) ? jsonable_live_result(value.to_h) : value
    end
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
    auth = JSON.parse(File.read(path))
    auth[provider]
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
    return creds["access_token"] if defined?(VCR) && VCR.current_cassette && !creds["access_token"].to_s.empty?

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
