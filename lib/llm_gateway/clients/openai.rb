# frozen_string_literal: true

require "time"

require_relative "../base_client"

module LlmGateway
  module Clients
    class OpenAI < BaseClient
      CODEX_BASE_ENDPOINT = "https://chatgpt.com/backend-api/codex"
      DEFAULT_MODEL = "gpt-4o"
      DEFAULT_EMBEDDINGS_MODEL = "text-embedding-3-small"

      attr_reader :account_id

      def initialize(api_key: ENV["OPENAI_API_KEY"], account_id: nil)
        @base_endpoint = "https://api.openai.com/v1"
        @account_id = account_id
        super(api_key: api_key)
      end

      def chat(messages, tools: nil, system: [], model: DEFAULT_MODEL, **options)
        body = {
          model: model,
          messages: system + messages
        }
        body[:tools] = tools if tools
        body.merge!(options)

        post("chat/completions", body)
      end

      def stream(messages, tools: nil, system: [], model: DEFAULT_MODEL, **options, &block)
        body = {
          model: model,
          messages: system + messages
        }
        body[:tools] = tools if tools
        body.merge!(options)
        body[:stream_options] = (body[:stream_options] || {}).merge(include_usage: true)

        post_stream("chat/completions", body, &block)
      end

      def responses(messages, tools: nil, system: [], model: DEFAULT_MODEL, **options)
        body = {
          model: model,
          input: messages.flatten
        }
        body[:instructions] = system[0][:content] if system.any?
        body[:tools] = tools if tools
        body.merge!(options)

        post("responses", body)
      end

      def stream_responses(messages, tools: nil, system: [], model: DEFAULT_MODEL, **options, &block)
        body = {
          model: model,
          input: messages.flatten
        }
        body[:instructions] = system[0][:content] if system.any?
        body[:tools] = tools if tools
        body.merge!(options)

        post_stream("responses", body, &block)
      end

      def get_oauth_access_token(access_token:, refresh_token:, expires_at:, account_id: nil, &block)
        token_manager = LlmGateway::Clients::OpenAI::TokenManager.new(
          access_token: access_token,
          refresh_token: refresh_token,
          expires_at: expires_at,
          account_id: account_id
        )
        token_manager.on_token_refresh = block if block_given?
        token_manager.ensure_valid_token
        token_manager.access_token
      end

      def chat_codex(messages, tools: nil, system: [], account_id: nil, model: DEFAULT_MODEL, **options)
        body = build_codex_body(messages, system, tools, model: model, **options)

        completed_response = nil
        post_codex_stream("responses", body, account_id: account_id) do |raw_sse|
          if raw_sse[:event] == "response.completed"
            completed_response = raw_sse.dig(:data, :response)
          end
        end

        completed_response
      end

      def stream_codex(messages, tools: nil, system: [], account_id: nil, model: DEFAULT_MODEL, **options, &block)
        body = build_codex_body(messages, system, tools, model: model, **options)
        post_codex_stream("responses", body, account_id: account_id, &block)
      end

      def download_file(file_id)
        get("files/#{file_id}/content")
      end

      def generate_embeddings(input, model: DEFAULT_EMBEDDINGS_MODEL)
        body = {
          input:,
          model: model
        }
        post("embeddings", body)
      end

      def upload_file(filename, content, mime_type = "application/octet-stream", purpose: "user_data")
        post_file("files", content, filename, purpose: purpose, mime_type: mime_type)
      end

      private

      def build_codex_body(messages, system, tools, model:, **options)
        instructions = Array(system).filter_map { |s| s.is_a?(Hash) ? s[:content] : s }.join("\n")
        instructions = instructions.presence || "You are a helpful assistant."

        body = {
          model: model,
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

      def rate_limit_error_options(response, error)
        info = rate_limit_info(response, error)
        return {} if info.empty?

        {
          reset_at: info[:primary_reset_at] || info[:reset_at],
          reset_after_seconds: info[:primary_reset_after_seconds] || info[:reset_after_seconds],
          rate_limit_info: info
        }
      end

      def rate_limit_info(response, error)
        headers = response_headers(response)
        codex_headers = headers.select { |key, _value| key.start_with?("x-codex-") }
        info = {}

        info[:provider] = "openai_codex" if codex_headers.any?
        info[:error_type] = error["type"]
        info[:plan_type] = headers["x-codex-plan-type"] || error["plan_type"]
        info[:active_limit] = headers["x-codex-active-limit"]
        info[:primary_used_percent] = integer_header(headers, "x-codex-primary-used-percent")
        info[:secondary_used_percent] = integer_header(headers, "x-codex-secondary-used-percent")
        info[:primary_window_minutes] = integer_header(headers, "x-codex-primary-window-minutes")
        info[:secondary_window_minutes] = integer_header(headers, "x-codex-secondary-window-minutes")
        info[:primary_over_secondary_limit_percent] = integer_header(headers, "x-codex-primary-over-secondary-limit-percent")
        info[:primary_reset_after_seconds] = integer_header(headers, "x-codex-primary-reset-after-seconds")
        info[:secondary_reset_after_seconds] = integer_header(headers, "x-codex-secondary-reset-after-seconds")
        info[:primary_reset_at] = epoch_time(headers["x-codex-primary-reset-at"])
        info[:secondary_reset_at] = epoch_time(headers["x-codex-secondary-reset-at"])
        info[:credits_has_credits] = boolean_header(headers, "x-codex-credits-has-credits")
        info[:credits_balance] = integer_header(headers, "x-codex-credits-balance")
        info[:credits_unlimited] = boolean_header(headers, "x-codex-credits-unlimited")
        info[:reset_after_seconds] = integer_value(error["resets_in_seconds"]) || retry_after_seconds(headers["retry-after"])
        info[:reset_at] = epoch_time(error["resets_at"]) || retry_after_time(headers["retry-after"])

        info.compact
      end

      def response_headers(response)
        headers = {}
        response.each_header { |key, value| headers[key.downcase] = value }
        headers
      end

      def integer_header(headers, key)
        integer_value(headers[key])
      end

      def integer_value(value)
        return nil if value.nil?

        Integer(value)
      rescue ArgumentError, TypeError
        nil
      end

      def boolean_header(headers, key)
        case headers[key].to_s.downcase
        when "true" then true
        when "false" then false
        end
      end

      def epoch_time(value)
        integer = integer_value(value)
        Time.at(integer) if integer
      end

      def retry_after_seconds(value)
        integer_value(value)
      end

      def retry_after_time(value)
        seconds = retry_after_seconds(value)
        return Time.now + seconds if seconds

        Time.httpdate(value)
      rescue ArgumentError, TypeError
        nil
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
          raise Errors::RateLimitError.new(error_message, error_code, **rate_limit_error_options(response, error))
        when 503
          raise Errors::OverloadError.new(error_message, error_code)
        end
        # If we get here, we didn't handle it specifically
        fallback_body = response.body.to_s.strip
        fallback_message = if fallback_body.blank?
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
