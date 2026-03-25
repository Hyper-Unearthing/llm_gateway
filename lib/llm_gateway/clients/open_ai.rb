# frozen_string_literal: true

require_relative "../base_client"

module LlmGateway
  module Clients
    class OpenAi < BaseClient
      def initialize(model_key: "gpt-4o", api_key: ENV["OPENAI_API_KEY"])
        @base_endpoint = "https://api.openai.com/v1"
        super(model_key: model_key, api_key: api_key)
      end

      def chat(messages, **kwargs)
        post("chat/completions", build_body_chat(messages, **kwargs))
      end

      def stream(messages, **kwargs, &block)
        body = build_body_chat(messages, **kwargs)
        body[:stream_options] = (body[:stream_options] || {}).merge(include_usage: true)
        post_stream("chat/completions", body, &block)
      end

      def responses(messages, **kwargs)
        body = build_body_responses(
          messages,
          **kwargs
        )
        post("responses", body)
      end

      def stream_responses(messages, **kwargs, &block)
        post_stream("responses", build_body_responses(messages, **kwargs), &block)
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

      def build_body_responses(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096, reasoning: nil, **options)
        body = {
          model: model_key,
          max_output_tokens: max_completion_tokens,
          input: messages.flatten
        }
        body[:instructions] = system[0][:content] if system.any?
        body[:tools] = tools if tools

        body[:reasoning] = reasoning if reasoning

        body.merge!(options)

        body
      end

      def build_body_chat(messages, response_format: { type: "text" }, tools: nil, system: [], max_completion_tokens: 4096, reasoning: nil, **options)
        body = {
          model: model_key,
          messages: system + messages,
          max_completion_tokens: max_completion_tokens
        }
        body[:tools] = tools if tools
        body[:response_format] = response_format unless response_format == { type: "text" }
        body[:reasoning_effort] = reasoning if reasoning
        body.merge!(options)

        body
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

        case response.code.to_i
        when 429
          raise Errors::RateLimitError.new(error["message"], error_code)
        when 503
          raise Errors::OverloadError.new(error["message"], error_code)
        end

        # If we get here, we didn't handle it specifically
        raise Errors::APIStatusError.new(error["message"], error_code)
      end
    end
  end
end
