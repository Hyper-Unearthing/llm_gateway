# frozen_string_literal: true

require_relative "structs"

module LlmGateway
  module Adapters
    class Adapter
      attr_reader :client, :provider, :adapter_id

      def initialize(client, provider:, adapter_id:)
        @client = client
        @provider = provider
        @adapter_id = adapter_id
      end

      def raw_stream(message, model:, tools: nil, system: nil, **options, &block)
        provider_model_key = LlmGateway.models.provider_model_key_for!(model, provider: provider, adapter: adapter_id)
        normalized_input = map_input({
          messages: sanitize_messages(normalize_messages(message), target_model: provider_model_key),
          tools: tools,
          system: normalize_system(system)
        })

        perform_stream(
          normalized_input[:messages],
          tools: normalized_input[:tools],
          system: normalized_input[:system],
          **map_options(options.merge(model: provider_model_key)),
          &block
        )
      end

      def stream(message, model:, tools: nil, system: nil, **options, &block)
        raise LlmGateway::Errors::MissingMapperForProvider, "No stream_mapper configured" unless stream_mapper

        mapper = stream_mapper.new(
          provider: provider,
          api: api_name,
          model_definition: model
        )

        raw_stream(message, model: model, tools: tools, system: system, **options) do |chunk|
          mapper.map(chunk, &block)
        end

        mapper.result
      end

      # Used by agents to validate a candidate before starting a stream.
      def validate_model!(model)
        LlmGateway.models.validate_compatibility!(model, provider: provider, adapter: adapter_id)
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

      def file_output_mapper
        nil
      end

      def option_mapper
        OptionMapper
      end

      def map_input(input)
        input_mapper.map(input)
      end

      def map_options(options)
        option_mapper.map(options)
      end

      def perform_stream(messages, tools:, system:, **options, &block)
        client.stream(messages, tools: tools, system: system, **options, &block)
      end

      public

      # Proxy adapters use these to normalize the target provider's raw stream.
      def stream_api_name
        api_name
      end

      def stream_mapper_class
        stream_mapper
      end

      private

      def api_name
        self.class.name.split("::").last.gsub(/Adapter$/, "").downcase
      end

      def stream_mapper
        nil
      end

      def sanitize_messages(messages, target_model: nil)
        return messages unless input_sanitizer

        return messages unless provider.present? && api_name.present? && target_model.present?

        input_sanitizer.sanitize(
          messages,
          target_provider: provider,
          target_api: api_name,
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
        message.is_a?(String) ? [ { role: "user", content: message } ] : message
      end
    end
  end
end
