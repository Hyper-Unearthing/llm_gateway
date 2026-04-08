# frozen_string_literal: true

require "uri"
require_relative "../base_client"
require_relative "claude_code/oauth_flow"
require_relative "claude_code/token_manager"

module LlmGateway
  module Clients
    class Anthropic < BaseClient
      CLAUDE_CODE_VERSION = "2.1.2"

      def initialize(model_key: "claude-3-7-sonnet-20250219", api_key: ENV["ANTHROPIC_API_KEY"])
        @base_endpoint = "https://api.anthropic.com/v1"
        super(model_key: model_key, api_key: api_key)
      end

      def chat(messages, **kwargs)
        post("messages", build_body(messages, **kwargs))
      end

      def stream(messages, **kwargs, &block)
        post_stream("messages", build_body(messages, **kwargs), &block)
      end

      def get_oauth_access_token(access_token:, refresh_token:, expires_at:, &block)
        token_manager = LlmGateway::Clients::ClaudeCode::TokenManager.new(
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at
        )
        token_manager.on_token_refresh = block if block_given?
        token_manager.ensure_valid_token
        token_manager.access_token
      end

      def download_file(file_id)
        get("files/#{file_id}/content")
      end

      def upload_file(filename, content, mime_type = "application/octet-stream")
        post_file("files", content, filename, mime_type: mime_type)
      end

      private

      def build_body(messages, tools: nil, system: [], cache_retention: nil, **options)
        cache_control = anthropic_cache_control_for(cache_retention)

        body = {
          model: model_key,
          messages: messages
        }

        tools = apply_tools_cache_control(tools, cache_retention)
        body.merge!(tools: tools) if LlmGateway::Utils.present?(tools)

        system = prepend_claude_code_identity(system) if claude_code_oauth_api_key?
        system = apply_system_cache_control(system, cache_retention)

        body.merge!(system: system) if LlmGateway::Utils.present?(system)
        body.merge!(cache_control: cache_control) unless cache_control.nil?
        body.merge!(options)
        body
      end

      def apply_system_cache_control(system, cache_retention)
        return system if system.nil? || system.empty? || !system.is_a?(Array)

        cache_control = anthropic_cache_control_for(cache_retention)
        return system if cache_control.nil?

        last_index = system.length - 1
        system.each_with_index.map do |block, index|
          block = block.dup
          if index == last_index
            block[:cache_control] = cache_control
          else
            block.delete(:cache_control)
          end
          block
        end
      end

      def apply_tools_cache_control(tools, cache_retention)
        return tools if tools.nil? || tools.empty? || !tools.is_a?(Array)

        cache_control = anthropic_cache_control_for(cache_retention)
        return tools if cache_control.nil?

        last_index = tools.length - 1
        tools.each_with_index.map do |tool, index|
          tool = tool.dup
          if index == last_index
            tool[:cache_control] = cache_control
          else
            tool.delete(:cache_control)
          end
          tool
        end
      end

      def anthropic_cache_control_for(cache_retention)
        return nil if cache_retention.nil?

        retention = cache_retention.to_s
        return nil if retention == "none"

        cache_control = { type: "ephemeral" }
        cache_control = cache_control.merge(ttl: "1h") if retention == "long" && anthropic_official_api?
        cache_control
      end

      def anthropic_official_api?
        URI(base_endpoint).host == "api.anthropic.com"
      end

      def build_headers
        return claude_code_oauth_headers if claude_code_oauth_api_key?

        {
          "anthropic-version" => "2023-06-01",
          "content-type" => "application/json",
          "x-api-key" => api_key,
          "anthropic-beta" => "code-execution-2025-05-22,files-api-2025-04-14"
        }
      end

      def claude_code_oauth_api_key?
        api_key.to_s.start_with?("sk-ant-oat")
      end

      def claude_code_oauth_headers
        {
          "anthropic-version" => "2023-06-01",
          "content-type" => "application/json",
          "Authorization" => "Bearer #{api_key}",
          "anthropic-dangerous-direct-browser-access" => "true",
          "anthropic-beta" => "claude-code-20250219,oauth-2025-04-20",
          "user-agent" => "claude-cli/#{CLAUDE_CODE_VERSION} (external, cli)",
          "x-app" => "cli"
        }
      end

      def prepend_claude_code_identity(system)
        identity = {
          type: "text",
          text: "You are Claude Code, Anthropic's official CLI for Claude."
        }

        if system.nil? || system.empty?
          [ identity ]
        else
          [ identity ] + system
        end
      end

      def handle_client_specific_errors(response, error)
        if Errors.context_overflow_message?(error["message"])
          raise Errors::PromptTooLong.new(error["message"], error["type"])
        end

        raise Errors::APIStatusError.new(error["message"], error["type"])
      end
    end
  end
end
