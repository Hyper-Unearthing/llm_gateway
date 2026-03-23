#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "json"
require_relative "../lib/llm_gateway"

module Scripts
  class CreateAnthropicCredentials
    def initialize(argv)
      @options = {
        client_id: LlmGateway::Clients::ClaudeCode::OAuthFlow::CLIENT_ID,
        scopes: LlmGateway::Clients::ClaudeCode::OAuthFlow::DEFAULT_SCOPES,
        output: nil
      }
      parse_options(argv)
    end

    def run
      flow = LlmGateway::Clients::ClaudeCode::OAuthFlow.new(
        client_id: @options[:client_id],
        scopes: @options[:scopes]
      )

      auth = flow.start

      puts "Anthropic OAuth setup"
      puts "Redirect URI: #{flow.redirect_uri}"
      puts ""
      puts "Open this URL in your browser:"
      puts auth[:authorization_url]
      puts ""
      puts "After authenticating, paste either:"
      puts "- the full callback URL"
      puts "- or the legacy code#state value"
      print "> "

      callback_value = $stdin.gets.to_s.strip
      tokens = flow.exchange_code(callback_value, auth[:code_verifier], state: auth[:state])

      credentials = {
        type: "oauth",
        clientId: flow.client_id,
        accessToken: tokens[:access_token],
        refreshToken: tokens[:refresh_token],
        expiresAt: tokens[:expires_at]&.iso8601
      }

      if @options[:output]
        File.write(@options[:output], JSON.pretty_generate(credentials) + "\n")
        puts "Credentials written to #{@options[:output]}"
      end

      puts "Credentials:"
      puts JSON.pretty_generate(credentials)
      puts ""
      puts "Environment exports:"
      puts "export ANTHROPIC_ACCESS_TOKEN=#{shell_escape(tokens[:access_token])}"
      puts "export ANTHROPIC_REFRESH_TOKEN=#{shell_escape(tokens[:refresh_token])}"
      puts "export ANTHROPIC_EXPIRES_AT=#{shell_escape(tokens[:expires_at]&.iso8601.to_s)}"
    rescue Interrupt
      warn "Aborted."
      exit 1
    end

    private

    def parse_options(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage: ruby scripts/create_anthropic_credentials.rb [options]"

        opts.on("--client-id ID", "Anthropic OAuth client id") do |value|
          @options[:client_id] = value
        end

        opts.on("--scopes SCOPES", "OAuth scopes") do |value|
          @options[:scopes] = value
        end

        opts.on("--output PATH", "Write credentials JSON to PATH") do |value|
          @options[:output] = value
        end
      end.parse!(argv)
    end

    def shell_escape(value)
      return "''" if value.nil? || value.empty?

      "'#{value.to_s.gsub("'", %q('\''))}'"
    end
  end
end

Scripts::CreateAnthropicCredentials.new(ARGV).run
