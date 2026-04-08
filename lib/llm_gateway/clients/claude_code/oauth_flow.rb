# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "digest"
require "base64"
require "uri"
require "time"

module LlmGateway
  module Clients
    module ClaudeCode
      class OAuthFlow
        CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        TOKEN_URL = "https://api.anthropic.com/v1/oauth/token"
        AUTH_URL = "https://claude.ai/oauth/authorize"
        REDIRECT_URI = "https://console.anthropic.com/oauth/code/callback"
        DEFAULT_SCOPES = "org:create_api_key user:profile user:inference"

        attr_reader :client_id, :redirect_uri, :scopes

        def initialize(
          client_id: CLIENT_ID,
          redirect_uri: REDIRECT_URI,
          scopes: DEFAULT_SCOPES
        )
          @client_id = client_id
          @redirect_uri = redirect_uri
          @scopes = scopes
        end

        # Step 1: Generate the authorization URL for the user to visit.
        # Returns a hash with everything needed to complete the flow later.
        def start(state: SecureRandom.hex(16))
          code_verifier, code_challenge = generate_pkce

          auth_url = build_authorization_url(code_challenge, state)

          {
            authorization_url: auth_url,
            code_verifier: code_verifier,
            state: state
          }
        end

        # Step 2: Exchange the authorization code for tokens.
        # Accepts one of:
        # - "code#state" (legacy format)
        # - a raw authorization code, with state passed separately
        # - a full callback URL containing ?code=...&state=...
        # Returns { access_token:, refresh_token:, expires_at: }
        def exchange_code(auth_code_or_callback, code_verifier, state: nil)
          code, resolved_state = extract_code_and_state(auth_code_or_callback, state)

          uri = URI(TOKEN_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = true
          http.read_timeout = 30
          http.open_timeout = 10

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"

          request.body = {
            grant_type: "authorization_code",
            client_id: @client_id,
            code: code,
            state: resolved_state || "",
            redirect_uri: @redirect_uri,
            code_verifier: code_verifier
          }.to_json

          response = http.request(request)

          if response.code.to_i == 200
            data = JSON.parse(response.body)

            expires_at = if data["expires_in"]
                           Time.now + data["expires_in"].to_i
            elsif data["expires_at"]
                           Time.parse(data["expires_at"])
            end

            {
              access_token: data["access_token"],
              refresh_token: data["refresh_token"],
              expires_at: expires_at
            }
          else
            error_body = begin
              JSON.parse(response.body)
            rescue StandardError
              {}
            end
            raise Errors::AuthenticationError.new(
              "OAuth token exchange failed: #{error_body["error_description"] || error_body["error"] || response.body}",
              error_body["error"]
            )
          end
        end

        def parse_callback(callback_url)
          uri = URI(callback_url)
          code = uri.query && URI.decode_www_form(uri.query).to_h["code"]
          state = uri.query && URI.decode_www_form(uri.query).to_h["state"]

          raise ArgumentError, "Callback URL is missing code parameter" if code.nil? || code.empty?

          { code: code, state: state }
        rescue URI::InvalidURIError => e
          raise ArgumentError, "Invalid callback URL: #{e.message}"
        end

        private

        def extract_code_and_state(auth_code_or_callback, state)
          value = auth_code_or_callback.to_s.strip
          raise ArgumentError, "Authorization code is required" if value.empty?

          if looks_like_url?(value)
            callback = parse_callback(value)
            [ callback[:code], callback[:state] || state ]
          elsif value.include?("#")
            code, parsed_state = value.split("#", 2)
            [ code, parsed_state || state ]
          else
            [ value, state ]
          end
        end

        def looks_like_url?(value)
          value.start_with?("http://", "https://")
        end

        def generate_pkce
          code_verifier = [ SecureRandom.random_bytes(32) ].pack("m0").tr("+/", "-_").tr("=", "")

          digest = Digest::SHA256.digest(code_verifier)
          code_challenge = [ digest ].pack("m0").tr("+/", "-_").tr("=", "")

          [ code_verifier, code_challenge ]
        end

        def build_authorization_url(code_challenge, state)
          params = {
            code: "true",
            client_id: @client_id,
            response_type: "code",
            redirect_uri: @redirect_uri,
            scope: @scopes,
            code_challenge: code_challenge,
            code_challenge_method: "S256",
            state: state
          }

          "#{AUTH_URL}?#{URI.encode_www_form(params)}"
        end
      end
    end
  end
end
