# frozen_string_literal: true

require "net/http"
require "json"
require "time"

module LlmGateway
  module Clients
    class ClaudeCode < Claude
      class TokenManager
        ANTHROPIC_OAUTH_TOKEN_URL = "https://api.anthropic.com/v1/oauth/token"

        attr_reader :refresh_token, :expires_at, :client_id, :client_secret, :access_token
        attr_accessor :on_token_refresh

        def initialize(
          access_token: nil,
          refresh_token:,
          expires_at: nil,
          client_id: ENV["ANTHROPIC_CLIENT_ID"],
          client_secret: ENV["ANTHROPIC_CLIENT_SECRET"]
        )
          @access_token = access_token
          @refresh_token = refresh_token
          @expires_at = parse_expires_at(expires_at)
          @client_id = client_id
          @client_secret = client_secret
          @on_token_refresh = nil
        end

        def token_expired?
          return true if @expires_at.nil?
          Time.now >= @expires_at
        end

        def ensure_valid_token
          refresh_access_token if token_expired?
        end

        def refresh_access_token
          raise ArgumentError, "Cannot refresh token: refresh_token not provided" unless @refresh_token
          raise ArgumentError, "Cannot refresh token: client_id not provided" unless @client_id
          raise ArgumentError, "Cannot refresh token: client_secret not provided" unless @client_secret

          uri = URI(ANTHROPIC_OAUTH_TOKEN_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = 30
          http.open_timeout = 10

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"

          body_params = {
            grant_type: "refresh_token",
            refresh_token: @refresh_token,
            client_id: @client_id,
            client_secret: @client_secret
          }
          request.body = URI.encode_www_form(body_params)

          response = http.request(request)

          if response.code.to_i == 200
            data = JSON.parse(response.body)
            @access_token = data["access_token"]

            if data["refresh_token"]
              @refresh_token = data["refresh_token"]
            end

            if data["expires_in"]
              @expires_at = Time.now + data["expires_in"].to_i
            elsif data["expires_at"]
              @expires_at = Time.parse(data["expires_at"])
            end

            @on_token_refresh&.call(@access_token, @refresh_token, @expires_at)

            @access_token
          else
            error_body = begin
              JSON.parse(response.body)
            rescue StandardError
              {}
            end
            raise Errors::AuthenticationError.new(
              "Failed to refresh token: #{error_body['error'] || response.body}",
              error_body["error_code"]
            )
          end
        end

        private

        def parse_expires_at(expires)
          case expires
          when Time
            expires
          when String
            Time.parse(expires)
          when Integer
            Time.at(expires)
          else
            nil
          end
        end
      end
    end
  end
end
