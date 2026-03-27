#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "json"
require_relative "../lib/llm_gateway"

module Scripts
  class CreateOpenAiCodexCredentials
    def initialize(argv)
      @options = {
        client_id: LlmGateway::Clients::OpenAiCodex::OAuthFlow::CLIENT_ID,
        redirect_uri: LlmGateway::Clients::OpenAiCodex::OAuthFlow::REDIRECT_URI,
        scope: LlmGateway::Clients::OpenAiCodex::OAuthFlow::SCOPE,
        output: nil
      }
      parse_options(argv)
    end

    def run
      flow = LlmGateway::Clients::OpenAiCodex::OAuthFlow.new(
        client_id: @options[:client_id],
        redirect_uri: @options[:redirect_uri],
        scope: @options[:scope]
      )

      auth = flow.start

      puts "OpenAI Codex OAuth setup"
      puts "Redirect URI: #{flow.redirect_uri}"
      puts ""
      puts "Open this URL in your browser:"
      puts auth[:authorization_url]
      puts ""
      puts "After authenticating, the browser will redirect to localhost (the page won't load)."
      puts "Paste either:"
      puts "  - the full callback URL  (http://localhost:1455/auth/callback?code=...)"
      puts "  - or just the code"
      print "> "

      callback_value = $stdin.gets.to_s.strip
      tokens = flow.exchange_code(callback_value, auth[:code_verifier], expected_state: auth[:state])

      credentials = {
        client_id: flow.client_id,
        account_id: tokens[:account_id],
        access_token: tokens[:access_token],
        refresh_token: tokens[:refresh_token],
        expires_at: tokens[:expires_at]&.iso8601
      }

      if @options[:output]
        File.write(@options[:output], JSON.pretty_generate(credentials) + "\n")
        puts "Credentials written to #{@options[:output]}"
      end

      puts ""
      puts "Credentials:"
      puts JSON.pretty_generate(credentials)
      puts ""
      puts "Environment exports:"
      puts "export OPENAI_CODEX_ACCOUNT_ID=#{shell_escape(tokens[:account_id].to_s)}"
      puts "export OPENAI_CODEX_ACCESS_TOKEN=#{shell_escape(tokens[:access_token])}"
      puts "export OPENAI_CODEX_REFRESH_TOKEN=#{shell_escape(tokens[:refresh_token])}"
      puts "export OPENAI_CODEX_EXPIRES_AT=#{shell_escape(tokens[:expires_at]&.iso8601.to_s)}"
    rescue Interrupt
      warn "Aborted."
      exit 1
    end

    private

    def parse_options(argv)
      OptionParser.new do |opts|
        opts.banner = "Usage: ruby scripts/create_openai_codex_credentials.rb [options]"

        opts.on("--client-id ID", "OpenAI OAuth client id") do |value|
          @options[:client_id] = value
        end

        opts.on("--redirect-uri URI", "OAuth redirect URI") do |value|
          @options[:redirect_uri] = value
        end

        opts.on("--scope SCOPE", "OAuth scopes (space-separated)") do |value|
          @options[:scope] = value
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

Scripts::CreateOpenAiCodexCredentials.new(ARGV).run
