# frozen_string_literal: true

require "net/http"
require "json"
require "securerandom"
require "digest"
require "base64"
require "uri"

module LlmGateway
  module Clients
    class ClaudeCode < Claude
      class OAuthFlow
        CLIENT_ID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
        TOKEN_URL = "https://console.anthropic.com/v1/oauth/token"
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
        def start
          code_verifier, code_challenge = generate_pkce

          auth_url = build_authorization_url(code_challenge)

          {
            authorization_url: auth_url,
            code_verifier: code_verifier
          }
        end

        # Step 2: Exchange the authorization code (pasted by user) for tokens.
        # The pasted value is in "code#state" format.
        # Returns { access_token:, refresh_token:, expires_at: }
        def exchange_code(auth_code, code_verifier)
          code, state = auth_code.split("#", 2)

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
            state: state || "",
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

        private

        def generate_pkce
          code_verifier = [SecureRandom.random_bytes(32)].pack("m0").tr("+/", "-_").tr("=", "")

          digest = Digest::SHA256.digest(code_verifier)
          code_challenge = [digest].pack("m0").tr("+/", "-_").tr("=", "")

          [code_verifier, code_challenge]
        end

        def build_authorization_url(code_challenge)
          params = {
            code: "true",
            client_id: @client_id,
            response_type: "code",
            redirect_uri: @redirect_uri,
            scope: @scopes,
            code_challenge: code_challenge,
            code_challenge_method: "S256",
            state: SecureRandom.hex(16)
          }

          "#{AUTH_URL}?#{URI.encode_www_form(params)}"
        end
      end
    end
  end
end
