# frozen_string_literal: true

require "test_helper"
require_relative "../../utils/live_test_helper"
require "socket"
require "stringio"

class ProxyServerClientTest < Test
  include LiveTestHelper

  PAIRS = [
    { name: "openai_apikey_completions", provider: "openai_completions", model: "gpt-5.1" },
    { name: "anthropic_apikey_messages", provider: "anthropic_messages", model: "claude-sonnet-4-20250514" },
    { name: "openai_apikey_responses", provider: "openai_responses", model: "gpt-5.4" },
    { name: "groq_completions", provider: "groq_completions", model: "openai/gpt-oss-120b", options: { reasoning: "none", include_reasoning: false, max_completion_tokens: 64 } }
  ].freeze

  def teardown
    LlmGateway.reset_configuration!
  end

  def self.define_proxy_test_for(name:, provider:, model:, oauth: false, options: {})
    test "proxy_server_client_streams_#{name}_#{model}" do
      with_proxy_server(provider:, oauth:) do |url|
        client = LlmGateway::Proxy::Client.new(
          url: url,
          target_provider: provider,
          target_config: {}
        )
        adapter = LlmGateway::Proxy::Adapter.new(client)

        events = []
        stream_options = { max_completion_tokens: 20, temperature: 0 }.merge(options)

        response = adapter.stream(
          "Reply with exactly these two words: proxy ok",
          model: model,
          **stream_options
        ) do |event|
          events << event
        end

        assert_instance_of AssistantMessage, response
        refute_empty response.provider
        refute_empty response.api
        refute_empty events

        text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
        assert_includes text, "proxy"
        assert_includes text, "ok"

        assert_stream_message_end_matches_response(
          events.find { |event| event.respond_to?(:type) && event.type.to_sym == :message_end },
          response
        )
      end
    end
  end

  PAIRS.each { |pair| define_proxy_test_for(**pair) }

  private

  def with_proxy_server(provider:, oauth:)
    cassette_name = vcr_cassette_name
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    proxy_app = LlmGateway::Proxy::Server.new

    VCR.configure { |config| config.ignore_hosts "127.0.0.1" }

    thread = Thread.new do
      Thread.current.report_on_exception = false
      socket = server.accept
      raw_request = read_http_request(socket)

      VCR.use_cassette(cassette_name, match_requests_on: %i[method uri json_body]) do
        status, headers, body = proxy_app.call(rack_env_for(raw_request, provider: provider, oauth: oauth))
        reason = RackReason.reason(status)
        socket.write "HTTP/1.1 #{status} #{reason}\r\n"
        headers.each { |key, value| socket.write "#{key}: #{value}\r\n" }
        socket.write "connection: close\r\n\r\n"
        body.each { |chunk| socket.write(chunk) }
      end
    rescue IOError
      # Server was closed before a request arrived.
    ensure
      socket&.close
    end

    yield "http://127.0.0.1:#{port}"
  ensure
    server&.close
    thread&.join(5)
    VCR.configure { |config| config.unignore_hosts "127.0.0.1" }
  end

  def rack_env_for(request, provider:, oauth:)
    body = JSON.parse(request.fetch(:body, "{}"))
    body["config"] = server_side_config_for(provider, oauth: oauth).merge(body["config"] || {})

    {
      "REQUEST_METHOD" => request.fetch(:method),
      "PATH_INFO" => request.fetch(:path),
      "rack.input" => StringIO.new(JSON.generate(body))
    }
  end

  def read_http_request(socket)
    request_line = socket.gets&.chomp
    method, path = request_line.to_s.split.first(2)
    headers = {}

    while (line = socket.gets)
      line = line.chomp
      break if line.empty?

      key, value = line.split(":", 2)
      headers[key.downcase] = value.to_s.strip if key
    end

    body = socket.read(headers.fetch("content-length", "0").to_i)
    { method: method, path: path, body: body }
  end

  module RackReason
    def self.reason(status)
      { 200 => "OK", 400 => "Bad Request", 404 => "Not Found", 500 => "Internal Server Error" }.fetch(status, "OK")
    end
  end

  def server_side_config_for(provider, oauth:)
    cassette_exists = File.exist?(vcr_cassette_path(vcr_cassette_name))

    if provider == "openai_codex"
      return { "api_key" => "vcr-replay-token", "account_id" => "vcr-replay-account" } if cassette_exists

      return {
        "api_key" => oauth_access_token_for("openai"),
        "account_id" => load_auth_credentials("openai")["account_id"]
      }
    end

    if oauth == true && provider == "anthropic_messages"
      return { "api_key" => "sk-ant-oat-vcr-replay-token" } if cassette_exists

      return { "api_key" => oauth_access_token_for("anthropic") }
    end

    return { "api_key" => "vcr-replay-token" } if cassette_exists

    case provider
    when "openai_completions", "openai_responses"
      { "api_key" => ENV.fetch("OPENAI_API_KEY") }
    when "groq_completions"
      { "api_key" => ENV.fetch("GROQ_API_KEY") }
    when "anthropic_messages"
      { "api_key" => ENV.fetch("ANTHROPIC_API_KEY") }
    else
      {}
    end
  end
end
