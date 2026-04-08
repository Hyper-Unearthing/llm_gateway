# frozen_string_literal: true

require_relative "stream_accumulator"
require_relative "structs"

module LlmGateway
  module Adapters
    class Adapter
      attr_reader :client

      def initialize(client)
        @client = client
      end

      def chat(message, tools: nil, system: nil, **options)
        normalized_input = map_input({
          messages: sanitize_messages(normalize_messages(message)),
          tools: tools,
          system: normalize_system(system)
        })

        result = perform_chat(
          normalized_input[:messages],
          tools: normalized_input[:tools],
          system: normalized_input[:system],
          **map_options(options)
        )

        map_output(result)
      end

      def stream(message, tools: nil, system: nil, **options, &block)
        raise LlmGateway::Errors::MissingMapperForProvider, "No stream_mapper configured" unless stream_mapper

        normalized_input = map_input({
          messages: sanitize_messages(normalize_messages(message)),
          tools: tools,
          system: normalize_system(system)
        })

        accumulator = ::StreamAccumulator.new
        mapper = stream_mapper.new

        perform_stream(
          normalized_input[:messages],
          tools: normalized_input[:tools],
          system: normalized_input[:system],
          **map_options(options)
        ) do |chunk|
          event = mapper.map(chunk)
          accumulator.push(event)
          block.call(event) if block && event
        end

        AssistantMessage.new(
          accumulator.result.merge(
            provider: LlmGateway::Client.provider_id_from_client(client),
            api: api_name
          )
        )
      end

      def upload_file(filename:, content:, mime_type: "application/octet-stream", purpose: "assistants")
        raise LlmGateway::Errors::MissingMapperForProvider, "No file_output_mapper configured" unless file_output_mapper

        upload_params = client.method(:upload_file).parameters
        supports_purpose = upload_params.any? { |type, name| [ :key, :keyreq ].include?(type) && name == :purpose }

        result = if supports_purpose
          client.upload_file(filename, content, mime_type, purpose: purpose)
        else
          client.upload_file(filename, content, mime_type)
        end

        file_output_mapper.map(result)
      end

      def download_file(file_id:)
        raise LlmGateway::Errors::MissingMapperForProvider, "No file_output_mapper configured" unless file_output_mapper

        result = client.download_file(file_id)
        file_output_mapper.map(result)
      end

      private

      def input_mapper
        raise NotImplementedError, "#{self.class} must implement #input_mapper"
      end

      def input_sanitizer
        nil
      end

      def output_mapper
        raise NotImplementedError, "#{self.class} must implement #output_mapper"
      end

      def file_output_mapper
        nil
      end

      def option_mapper
        OptionMapper
      end

      def map_input(input)
        input_mapper.map(input)
      end

      def map_output(output)
        output_mapper.map(output)
      end

      def map_options(options)
        option_mapper.map(options)
      end

      def perform_chat(messages, tools:, system:, **options)
        client.chat(messages, tools: tools, system: system, **options)
      end

      def perform_stream(messages, tools:, system:, **options, &block)
        client.stream(messages, tools: tools, system: system, **options, &block)
      end

      def api_name
        self.class.name.split("::").last.gsub(/Adapter$/, "").downcase
      end

      def stream_mapper
        nil
      end

      def sanitize_messages(messages)
        return messages unless input_sanitizer

        target_provider = LlmGateway::Client.provider_id_from_client(client)
        target_api = api_name
        target_model = client.model_key

        return messages if target_provider.nil? || target_api.nil? || target_model.nil?

        input_sanitizer.sanitize(
          messages,
          target_provider: target_provider,
          target_api: target_api,
          target_model: target_model
        )
      end

      def normalize_system(system)
        if system.nil?
          []
        elsif system.is_a?(String)
          [ { role: "system", content: system } ]
        elsif system.is_a?(Array)
          system
        else
          raise ArgumentError, "System parameter must be a string or array, got #{system.class}"
        end
      end

      def normalize_messages(message)
        if message.is_a?(String)
          [ { role: "user", content: message } ]
        else
          message
        end
      end
    end
  end
end
