# frozen_string_literal: true

require "net/http"
require "json"
require "time"

module LlmGateway
  module Clients
    class OpenAi
      class TokenManager
        attr_reader :access_token, :refresh_token, :expires_at, :account_id, :client_id
        attr_accessor :on_token_refresh

        def initialize(
          access_token: nil,
          refresh_token:,
          expires_at: nil,
          account_id: nil,
          client_id: OAuthFlow::CLIENT_ID
        )
          @access_token  = access_token
          @refresh_token = refresh_token
          @expires_at    = parse_expires_at(expires_at)
          @account_id    = account_id
          @client_id     = client_id
          @on_token_refresh = nil
        end

        def token_expired?
          return true if @expires_at.nil?

          Time.now >= @expires_at
        end

        def ensure_valid_token
          refresh_access_token! if token_expired?
        end

        def refresh_access_token!
          raise ArgumentError, "Cannot refresh token: refresh_token not provided" unless @refresh_token

          result = OAuthFlow.refresh_access_token(@refresh_token, client_id: @client_id)

          @access_token  = result[:access_token]
          @refresh_token = result[:refresh_token]
          @expires_at    = result[:expires_at]
          @account_id    = result[:account_id] if result[:account_id]

          @on_token_refresh&.call(@access_token, @refresh_token, @expires_at)

          @access_token
        end

        private

        def parse_expires_at(expires)
          case expires
          when Time
            expires
          when String
            Time.parse(expires)
          when Integer, Float
            Time.at(expires.to_i)
          else
            nil
          end
        end
      end
    end
  end
end
