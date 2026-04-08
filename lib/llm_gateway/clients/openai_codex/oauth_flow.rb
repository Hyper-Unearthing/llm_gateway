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
    class OpenAI
      class OAuthFlow
        CLIENT_ID    = "app_EMoamEEZ73f0CkXaXp7hrann"
        AUTHORIZE_URL = "https://auth.openai.com/oauth/authorize"
        TOKEN_URL     = "https://auth.openai.com/oauth/token"
        REDIRECT_URI  = "http://localhost:1455/auth/callback"
        SCOPE         = "openid profile email offline_access"
        JWT_CLAIM_PATH = "https://api.openai.com/auth"

        attr_reader :client_id, :redirect_uri, :scope

        def initialize(
          client_id: CLIENT_ID,
          redirect_uri: REDIRECT_URI,
          scope: SCOPE
        )
          @client_id   = client_id
          @redirect_uri = redirect_uri
          @scope        = scope
        end

        # Step 1: Generate the authorization URL and PKCE values.
        # Returns { authorization_url:, code_verifier:, state: }
        def start(state: SecureRandom.hex(16))
          code_verifier, code_challenge = generate_pkce

          {
            authorization_url: build_authorization_url(code_challenge, state),
            code_verifier: code_verifier,
            state: state
          }
        end

        # Step 2: Exchange the authorization code for tokens.
        # Accepts a raw code string, a full redirect URL, or code#state format.
        # Returns { access_token:, refresh_token:, expires_at:, account_id: }
        def exchange_code(input, code_verifier, expected_state: nil)
          code = parse_authorization_input(input, expected_state)
          raise ArgumentError, "Missing authorization code" unless code

          uri     = URI(TOKEN_URL)
          http    = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.read_timeout = 30
          http.open_timeout = 10

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.body = URI.encode_www_form(
            grant_type: "authorization_code",
            client_id: @client_id,
            code: code,
            code_verifier: code_verifier,
            redirect_uri: @redirect_uri
          )

          response = http.request(request)

          if response.code.to_i == 200
            data = JSON.parse(response.body)

            unless data["access_token"] && data["refresh_token"] && data["expires_in"]
              raise "Token response missing required fields: #{data.keys.join(", ")}"
            end

            expires_at = Time.now + data["expires_in"].to_i
            account_id = self.class.extract_account_id_from_token(data["access_token"])
            raise "Failed to extract account_id from access token" unless account_id

            {
              access_token: data["access_token"],
              refresh_token: data["refresh_token"],
              expires_at: expires_at,
              account_id: account_id
            }
          else
            error_body = parse_error_body(response.body)
            raise "OAuth token exchange failed (#{response.code}): #{error_body["error_description"] || error_body["error"] || response.body}"
          end
        end

        # Parse a callback URL (or query string) into { code:, state: }
        def parse_callback(callback_url)
          uri    = URI.parse(callback_url)
          params = URI.decode_www_form(uri.query.to_s).to_h
          code   = params["code"]
          raise ArgumentError, "Callback URL is missing code parameter" if code.nil? || code.empty?

          { code: code, state: params["state"] }
        rescue URI::InvalidURIError => e
          raise ArgumentError, "Invalid callback URL: #{e.message}"
        end

        # Interactive OAuth flow: print URL, wait for paste, return tokens.
        # Returns { access_token:, refresh_token:, expires_at:, account_id: }
        def login
          flow = start

          puts "Open this URL to authorize with OpenAI:"
          puts flow[:authorization_url]
          puts
          puts "After logging in your browser will redirect to localhost (the page won't load)."
          puts "Copy the full URL from your browser's address bar and paste it below."
          puts
          print "Paste the redirect URL (or authorization code): "

          tty   = File.open("/dev/tty", "r")
          input = tty.gets&.strip
          tty.close

          raise "No authorization code provided" if input.nil? || input.empty?

          exchange_code(input, flow[:code_verifier], expected_state: flow[:state])
        end

        # Refresh an existing access token (class method).
        # Returns { access_token:, refresh_token:, expires_at:, account_id: }
        def self.refresh_access_token(refresh_token, client_id: CLIENT_ID)
          uri  = URI(TOKEN_URL)
          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl      = true
          http.read_timeout = 30
          http.open_timeout = 10

          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/x-www-form-urlencoded"
          request.body = URI.encode_www_form(
            grant_type: "refresh_token",
            refresh_token: refresh_token,
            client_id: client_id
          )

          response = http.request(request)

          if response.code.to_i == 200
            data = JSON.parse(response.body)

            unless data["access_token"] && data["refresh_token"] && data["expires_in"]
              raise "Token refresh response missing required fields"
            end

            expires_at = Time.now + data["expires_in"].to_i
            account_id = extract_account_id_from_token(data["access_token"])

            {
              access_token: data["access_token"],
              refresh_token: data["refresh_token"],
              expires_at: expires_at,
              account_id: account_id
            }
          else
            error_body = begin
              JSON.parse(response.body)
            rescue StandardError
              {}
            end
            raise "Token refresh failed (#{response.code}): #{error_body["error_description"] || error_body["error"] || response.body}"
          end
        end

        # Extract the ChatGPT account_id from a JWT access token.
        def self.extract_account_id_from_token(token)
          parts = token.to_s.split(".")
          return nil unless parts.length == 3

          payload_b64 = parts[1]
          # Re-pad to a multiple of 4 for base64 decoding
          payload_b64 += "=" * ((4 - payload_b64.length % 4) % 4)
          payload = JSON.parse(Base64.urlsafe_decode64(payload_b64))

          auth       = payload[JWT_CLAIM_PATH]
          account_id = auth&.dig("chatgpt_account_id")

          account_id.is_a?(String) && !account_id.empty? ? account_id : nil
        rescue StandardError
          nil
        end

        private

        def generate_pkce
          code_verifier  = SecureRandom.urlsafe_base64(32).tr("=", "")
          digest         = Digest::SHA256.digest(code_verifier)
          code_challenge = Base64.urlsafe_encode64(digest).tr("=", "")
          [ code_verifier, code_challenge ]
        end

        def build_authorization_url(code_challenge, state)
          params = {
            response_type: "code",
            client_id: @client_id,
            redirect_uri: @redirect_uri,
            scope: @scope,
            code_challenge: code_challenge,
            code_challenge_method: "S256",
            state: state,
            id_token_add_organizations: "true",
            codex_cli_simplified_flow: "true",
            originator: "llm_gateway"
          }
          "#{AUTHORIZE_URL}?#{URI.encode_www_form(params)}"
        end

        def parse_authorization_input(input, expected_state = nil)
          return nil if input.nil? || input.empty?

          value = input.to_s.strip

          # Full URL
          if value.start_with?("http://", "https://")
            parsed = parse_callback(value)
            if expected_state && parsed[:state] && parsed[:state] != expected_state
              raise "State mismatch"
            end
            return parsed[:code]
          end

          # code#state shorthand
          if value.include?("#")
            code, state = value.split("#", 2)
            raise "State mismatch" if expected_state && state && state != expected_state
            return code
          end

          # Query-string fragment
          if value.include?("code=")
            params = URI.decode_www_form(value).to_h
            if expected_state && params["state"] && params["state"] != expected_state
              raise "State mismatch"
            end
            return params["code"]
          end

          # Raw code
          value
        end

        def parse_error_body(body)
          JSON.parse(body)
        rescue StandardError
          {}
        end
      end
    end
  end
end
