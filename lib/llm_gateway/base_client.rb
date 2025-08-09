# frozen_string_literal: true

require "net/http"
require "stringio"
require "json"

module LlmGateway
  class BaseClient
    attr_accessor
    attr_reader :api_key, :model_key, :base_endpoint

    def initialize(model_key:, api_key:)
      @model_key = model_key
      @api_key = api_key
    end

    def get(url_part, extra_headers = {})
      endpoint = "#{base_endpoint}/#{url_part.sub(%r{^/}, "")}"
      response = make_request(endpoint, Net::HTTP::Get, nil, extra_headers)
      process_response(response)
    end

    def post_file(url_part, file_contents, filename, purpose: nil, mime_type: "application/octet-stream")
      endpoint = "#{base_endpoint}/#{url_part.sub(%r{^/}, "")}"
      uri = URI.parse(endpoint)

      file_io = StringIO.new(file_contents)

      # Create request with full URI (important!)
      request = Net::HTTP::Post.new(uri)

      form_data = [
        [
          "file",
          file_io,
          { filename: filename, "Content-Type" => mime_type }
        ]
      ]

      # Add purpose parameter if provided
      form_data << [ "purpose", purpose ] if purpose

      request.set_form(form_data, "multipart/form-data")

      # Headers (excluding Content-Type because set_form already sets it)
      multipart_headers = build_headers.reject { |k, _| k.downcase == "content-type" }
      multipart_headers.each { |key, value| request[key] = value }

      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end


      process_response(response)
    end

    def post(url_part, body = nil, extra_headers = {})
      endpoint = "#{base_endpoint}/#{url_part.sub(%r{^/}, "")}"
      response = make_request(endpoint, Net::HTTP::Post, body, extra_headers)
      process_response(response)
    end

    protected

    def make_request(endpoint, method, params = nil, extra_headers = {})
      uri = URI(endpoint)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.read_timeout = 480
      http.open_timeout = 10

      request = method.new(uri)
      headers = build_headers.merge(extra_headers)
      headers.each { |key, value| request[key] = value }
      request.body = params.to_json if params

      http.request(request)
    end

    def process_response(response)
      case response.code.to_i
      when 200
        content_type = response["content-type"]
        if content_type&.include?("application/json")
          LlmGateway::Utils.deep_symbolize_keys(JSON.parse(response.body))
        else
          response.body
        end
      else
        handle_error(response)
      end
    end

    def handle_error(response)
      error_body = begin
        JSON.parse(response.body)
      rescue StandardError
        {}
      end
      error = error_body["error"] || {}

      # Try client-specific error handling first
      begin
        handle_client_specific_errors(response, error)
      rescue Errors::APIStatusError => e
        # If client doesn't handle it, use standard HTTP status codes
        # Use the message and code that were already passed to APIStatusError
        case response.code.to_i
        when 400
          raise Errors::BadRequestError.new(e.message, e.code)
        when 401
          raise Errors::AuthenticationError.new(e.message, e.code)
        when 403
          raise Errors::PermissionDeniedError.new(e.message, e.code)
        when 404
          raise Errors::NotFoundError.new(e.message, e.code)
        when 409
          raise Errors::ConflictError.new(e.message, e.code)
        when 422
          raise Errors::UnprocessableEntityError.new(e.message, e.code)
        when 429
          raise Errors::RateLimitError.new(e.message, e.code)
        when 503
          raise Errors::OverloadError.new(e.message, e.code)
        when 500..599
          raise Errors::InternalServerError.new(e.message, e.code)
        else
          raise e # Re-raise the original APIStatusError
        end
      end
    end

    def build_headers
      raise NotImplementedError, "Subclasses must implement build_headers"
    end

    def handle_client_specific_errors(response, error); end
  end
end
