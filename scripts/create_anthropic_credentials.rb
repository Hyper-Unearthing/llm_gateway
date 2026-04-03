#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "json"
require "fileutils"
require_relative "../lib/llm_gateway"

module Scripts
  class CreateAnthropicCredentials
    def initialize(argv)
      @options = {
        client_id: LlmGateway::Clients::ClaudeCode::OAuthFlow::CLIENT_ID,
        scopes: LlmGateway::Clients::ClaudeCode::OAuthFlow::DEFAULT_SCOPES,
        output: File.expand_path(ENV.fetch("LLM_GATEWAY_AUTH_FILE", "~/.config/llm_gateway/auth.json"))
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
        client_id: flow.client_id,
        access_token: tokens[:access_token],
        refresh_token: tokens[:refresh_token],
        expires_at: tokens[:expires_at]&.iso8601
      }

      persist_credentials("anthropic", credentials)

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

    def persist_credentials(provider, credentials)
      output_path = File.expand_path(@options[:output])
      FileUtils.mkdir_p(File.dirname(output_path))

      existing = if File.exist?(output_path)
        JSON.parse(File.read(output_path))
      else
        {}
      end

      existing[provider] = credentials
      File.write(output_path, JSON.pretty_generate(existing) + "\n")
      puts "Credentials written to #{output_path}"
    end

    def shell_escape(value)
      return "''" if value.nil? || value.empty?

      "'#{value.to_s.gsub("'", %q('\''))}'"
    end
  end
end

Scripts::CreateAnthropicCredentials.new(ARGV).run
