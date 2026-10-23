# frozen_string_literal: true

require "test_helper"

class OpenAITokenManagerTest < Test
  TOKEN_URL = LlmGateway::Clients::OpenAI::OAuthFlow::TOKEN_URL

  def setup
    WebMock.reset!
    @manager = LlmGateway::Clients::OpenAI::TokenManager.new(
      access_token: "old-access", refresh_token: "old-refresh", expires_at: Time.now - 60, account_id: "account"
    )
    @refreshes = []
    @manager.on_token_refresh = ->(*tokens) { @refreshes << tokens }
  end

  test "valid tokens do not make a refresh request or call the callback" do
    manager = LlmGateway::Clients::OpenAI::TokenManager.new(
      access_token: "current", refresh_token: nil, expires_at: Time.now + 3600
    )
    manager.on_token_refresh = ->(*) { flunk "unexpected refresh" }
    manager.ensure_valid_token
    assert_equal "current", manager.access_token
    assert_not_requested :post, TOKEN_URL
  end

  test "expired and unknown expiry tokens rotate once and notify persistence" do
    [ Time.now - 60, nil ].each do |expiry|
      WebMock.reset!
      request = stub_refresh(body: { access_token: "new-access", refresh_token: "new-refresh", expires_in: 3600 }.to_json)
      manager = LlmGateway::Clients::OpenAI::TokenManager.new(
        access_token: "old-access", refresh_token: "old-refresh", expires_at: expiry, account_id: "account"
      )
      calls = []
      manager.on_token_refresh = ->(*tokens) { calls << tokens }
      manager.ensure_valid_token
      manager.ensure_valid_token
      assert_equal "new-access", manager.access_token
      assert_equal "new-refresh", manager.refresh_token
      assert_equal "account", manager.account_id
      assert_in_delta Time.now + 3600, manager.expires_at, 2
      assert_equal [ [ manager.access_token, manager.refresh_token, manager.expires_at ] ], calls
      assert_requested request, times: 1
    end
  end

  test "provider rejection exposes status and code without response content" do
    request = stub_refresh(status: 400, body: { error: "invalid_grant", error_description: "private-response" }.to_json)
    error = assert_failed_refresh
    assert_equal 400, error.status
    assert_equal "invalid_grant", error.code
    assert_equal :rejected, error.reason
    assert_requested request, times: 1
  end

  test "server failures retain status even when the body is not JSON" do
    stub_refresh(status: 503, body: "private-response")
    error = assert_failed_refresh
    assert_equal 503, error.status
    assert_nil error.code
    assert_equal :rejected, error.reason
  end

  test "malformed or sensitive error codes are not exposed" do
    [ "old-refresh", "private response", "x" * 129, { message: "private-response" } ].each do |code|
      stub_refresh(status: 400, body: { error: code }.to_json)
      assert_nil assert_failed_refresh.code
    end
  end

  test "invalid success responses do not mutate tokens or call persistence" do
    valid = { access_token: "new-access", refresh_token: "new-refresh", expires_in: 3600 }
    bodies = [ "private-response", "null", "[]", "{}" ]
    bodies += [ nil, "", " ", 123 ].flat_map do |value|
      [ valid.merge(access_token: value).to_json, valid.merge(refresh_token: value).to_json ]
    end
    bodies += [ nil, "invalid", 0, -1 ].map { |value| valid.merge(expires_in: value).to_json }
    bodies.each do |body|
      stub_refresh(body: body)
      error = assert_failed_refresh
      assert_equal 200, error.status
      assert_equal :invalid_response, error.reason
    end
  end

  test "transport failures are typed and not retried or chained" do
    [ Net::OpenTimeout, Net::ReadTimeout, SocketError, EOFError, Errno::ECONNRESET,
      Errno::ECONNREFUSED, Errno::EPIPE, OpenSSL::SSL::SSLError, Net::HTTPBadResponse ].each do |type|
      WebMock.reset!
      request = stub_request(:post, TOKEN_URL).to_raise(type.new("private-response"))
      error = assert_failed_refresh
      assert_equal :transport, error.reason
      assert_nil error.status
      assert_requested request, times: 1
    end
  end

  test "missing refresh tokens fail before making a request" do
    [ nil, "", " " ].each do |token|
      manager = LlmGateway::Clients::OpenAI::TokenManager.new(refresh_token: token)
      assert_raises(ArgumentError) { manager.ensure_valid_token }
    end
    assert_not_requested :post, TOKEN_URL
  end

  test "persistence callback failures are not disguised as provider errors" do
    stub_refresh(body: { access_token: "new-access", refresh_token: "new-refresh", expires_in: 3600 }.to_json)
    @manager.on_token_refresh = ->(*) { raise "persistence failed" }
    error = assert_raises(RuntimeError) { @manager.ensure_valid_token }
    assert_equal "persistence failed", error.message
  end

  def teardown
    WebMock.reset!
    super
  end

  private

  def stub_refresh(status: 200, body:)
    stub_request(:post, TOKEN_URL).with(body: {
      grant_type: "refresh_token",
      refresh_token: "old-refresh",
      client_id: LlmGateway::Clients::OpenAI::OAuthFlow::CLIENT_ID
    }).to_return(status: status, body: body)
  end

  def assert_failed_refresh
    error = assert_raises(LlmGateway::Errors::OAuthRefreshError) { @manager.ensure_valid_token }
    assert_equal "OAuth token refresh failed.", error.message
    assert_nil error.cause
    assert_equal "old-access", @manager.access_token
    assert_equal "old-refresh", @manager.refresh_token
    assert_equal "account", @manager.account_id
    assert_empty @refreshes
    error
  end
end
