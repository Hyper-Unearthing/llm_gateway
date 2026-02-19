# frozen_string_literal: true

module LlmGateway
  module Adapters
    class Adapter
      attr_reader :client, :input_mapper, :output_mapper, :file_output_mapper, :stream_output_mapper_class

      def initialize(client, input_mapper:, output_mapper:, file_output_mapper: nil, stream_output_mapper: nil)
        @client = client
        @input_mapper = input_mapper
        @output_mapper = output_mapper
        @file_output_mapper = file_output_mapper
        @stream_output_mapper_class = stream_output_mapper
      end

      def chat(message, response_format: "text", tools: nil, system: nil, &block)
        normalized_input = input_mapper.map({
          messages: normalize_messages(message),
          response_format: normalize_response_format(response_format),
          tools: tools,
          system: normalize_system(system)
        })

        if block_given?
          chat_streaming(normalized_input, &block)
        else
          chat_non_streaming(normalized_input)
        end
      end

      def upload_file(file, purpose: "assistants")
        raise LlmGateway::Errors::MissingMapperForProvider, "No file_output_mapper configured" unless file_output_mapper

        result = client.upload_file(file, purpose: purpose)
        file_output_mapper.map(result)
      end

      def download_file(file_id)
        raise LlmGateway::Errors::MissingMapperForProvider, "No file_output_mapper configured" unless file_output_mapper

        result = client.download_file(file_id)
        file_output_mapper.map(result)
      end

      private

      def chat_non_streaming(normalized_input)
        result = client.chat(
          normalized_input[:messages],
          response_format: normalized_input[:response_format],
          tools: normalized_input[:tools],
          system: normalized_input[:system]
        )
        output_mapper.map(result)
      end

      def chat_streaming(normalized_input, &block)
        raise "No stream_output_mapper configured for this adapter" unless stream_output_mapper_class

        stream_mapper = stream_output_mapper_class.new

        client.chat(
          normalized_input[:messages],
          response_format: normalized_input[:response_format],
          tools: normalized_input[:tools],
          system: normalized_input[:system]
        ) do |raw_sse|
          normalized_event = stream_mapper.map_event(raw_sse)
          yield normalized_event if normalized_event
        end

        accumulated = stream_mapper.to_message
        output_mapper.map(accumulated)
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

      def normalize_response_format(response_format)
        if response_format.is_a?(String)
          { type: response_format }
        else
          response_format
        end
      end
    end
  end
end
