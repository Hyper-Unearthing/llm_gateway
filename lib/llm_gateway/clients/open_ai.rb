# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class OpenAi < BaseClient
      CODEX_BASE_ENDPOINT = "https://chatgpt.com/backend-api/codex"

      attr_reader :account_id

      def initialize(model_key: "gpt-4o", api_key: ENV["OPENAI_API_KEY"], account_id: nil)
        @base_endpoint = "https://api.openai.com/v1"
        @account_id = account_id
        super(model_key: model_key, api_key: api_key)
      end

      def chat(messages, tools: nil, system: [], **options)
        body = {
          model: model_key,
          messages: system + messages
        }
        body[:tools] = tools if tools
        body.merge!(options)

        post("chat/completions", body)
      end

      def stream(messages, tools: nil, system: [], **options, &block)
        body = {
          model: model_key,
          messages: system + messages
        }
        body[:tools] = tools if tools
        body.merge!(options)
        body[:stream_options] = (body[:stream_options] || {}).merge(include_usage: true)

        post_stream("chat/completions", body, &block)
      end

      def responses(messages, tools: nil, system: [], **options)
        body = {
          model: model_key,
          input: messages.flatten
        }
        body[:instructions] = system[0][:content] if system.any?
        body[:tools] = tools if tools
        body.merge!(options)

        post("responses", body)
      end

      def stream_responses(messages, tools: nil, system: [], **options, &block)
        body = {
          model: model_key,
          input: messages.flatten
        }
        body[:instructions] = system[0][:content] if system.any?
        body[:tools] = tools if tools
        body.merge!(options)

        post_stream("responses", body, &block)
      end

      def get_oauth_access_token(access_token:, refresh_token:, expires_at:, account_id: nil, &block)
        token_manager = LlmGateway::Clients::OpenAi::TokenManager.new(
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at,
          account_id: account_id
        )
        token_manager.on_token_refresh = block if block_given?
        token_manager.ensure_valid_token
        token_manager.access_token
      end

      def chat_codex(messages, tools: nil, system: [], account_id: nil, **options)
        body = build_codex_body(messages, system, tools, **options)

        completed_response = nil
        post_codex_stream("responses", body, account_id: account_id) do |raw_sse|
          if raw_sse[:event] == "response.completed"
            completed_response = raw_sse.dig(:data, :response)
          end
        end

        completed_response
      end

      def stream_codex(messages, tools: nil, system: [], account_id: nil, **options, &block)
        body = build_codex_body(messages, system, tools, **options)
        post_codex_stream("responses", body, account_id: account_id, &block)
      end

      def download_file(file_id)
        get("files/#{file_id}/content")
      end

      def generate_embeddings(input)
        body = {
          input:,
          model: model_key
        }
        post("embeddings", body)
      end

      def upload_file(filename, content, mime_type = "application/octet-stream", purpose: "user_data")
        post_file("files", content, filename, purpose: purpose, mime_type: mime_type)
      end

      private

      def build_codex_body(messages, system, tools, **options)
        instructions = Array(system).filter_map { |s| s.is_a?(Hash) ? s[:content] : s }.join("\n")
        instructions = "You are a helpful assistant." if instructions.empty?

        body = {
          model: model_key,
          instructions: instructions,
          input: messages,
          store: false,
          include: [ "reasoning.encrypted_content" ],
          stream: true
        }

        body[:tools] = tools if tools
        body.merge!(options)

        body
      end

      def codex_headers(account_id: nil, **options)
        effective_account_id = account_id || @account_id

        headers = {
          "content-type" => "application/json",
          "Authorization" => "Bearer #{api_key}",
          "OpenAI-Beta" => "responses=experimental"
        }
        headers["chatgpt-account-id"] = effective_account_id if effective_account_id
        headers
      end

      def post_codex_stream(url_part, body = nil, account_id: nil, &block)
        endpoint = "#{CODEX_BASE_ENDPOINT}/#{url_part.sub(%r{^/}, "")}"
        uri = URI(endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 480
        http.open_timeout = 10

        body.merge!(stream: true)
        request = Net::HTTP::Post.new(uri)
        codex_headers(account_id: account_id).each { |key, value| request[key] = value }
        prompt_cache_key = body.delete(:prompt_cache_key)
        request[:session_id] = prompt_cache_key if prompt_cache_key

        request.body = body.to_json if body

        http.request(request) do |response|
          unless response.code.to_i == 200
            full_body = +""
            response.read_body { |chunk| full_body << chunk }
            response.instance_variable_set(:@body, full_body)
            response.instance_variable_set(:@read, true)
            handle_error(response)
          end

          parse_sse_stream(response, &block)
        end
      end

      def build_headers
        {
          "content-type" => "application/json",
          "Authorization" => "Bearer #{api_key}"
        }
      end

      def handle_client_specific_errors(response, error)
        # OpenAI uses 'code' instead of 'type' for error codes
        error_code = error["code"]
        error_message = error["message"]

        if Errors.context_overflow_message?(error_message)
          raise Errors::PromptTooLong.new(error_message, error_code)
        end

        case response.code.to_i
        when 429
          raise Errors::RateLimitError.new(error_message, error_code)
        when 503
          raise Errors::OverloadError.new(error_message, error_code)
        end
        # If we get here, we didn't handle it specifically
        fallback_body = response.body.to_s.strip
        fallback_message = if fallback_body.empty?
          "OpenAI request failed with status #{response.code}"
        else
          "OpenAI request failed with status #{response.code}: #{fallback_body}"
        end

        message = error["message"] || fallback_message
        raise Errors::APIStatusError.new(message, error_code)
      end
    end
  end
end
