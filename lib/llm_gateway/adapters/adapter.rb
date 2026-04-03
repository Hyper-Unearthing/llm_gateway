# frozen_string_literal: true

require_relative "stream_accumulator"
require_relative "structs"

module LlmGateway
  module Adapters
    class Adapter
      attr_reader :client, :input_mapper, :output_mapper, :file_output_mapper, :option_mapper, :client_method, :stream_mapper

      def initialize(client, input_mapper:, output_mapper:, file_output_mapper: nil, stream_mapper: nil, option_mapper: OptionMapper, client_method: :chat)
        @client = client
        @input_mapper = input_mapper
        @output_mapper = output_mapper
        @file_output_mapper = file_output_mapper
        @option_mapper = option_mapper
        @client_method = client_method
        @stream_mapper = stream_mapper
      end

      def chat(message, tools: nil, system: nil, **options)
        normalized_input = input_mapper.map({
          messages: normalize_messages(message),
          tools: tools,
          system: normalize_system(system)
        })

        client_kwargs = {
          tools: normalized_input[:tools],
          system: normalized_input[:system]
        }

        client_kwargs.merge!(option_mapper.map(options))

        result = client.public_send(client_method, normalized_input[:messages], **client_kwargs)
        output_mapper.map(result)
      end

      def stream(message, tools: nil, system: nil, **options, &block)
        raise LlmGateway::Errors::MissingMapperForProvider, "No stream_mapper configured" unless stream_mapper

        normalized_input = input_mapper.map({
          messages: normalize_messages(message),
          tools: tools,
          system: normalize_system(system)
        })

        accumulator = ::StreamAccumulator.new
        mapper = stream_mapper.new

        stream_kwargs = {
          tools: normalized_input[:tools],
          system: normalized_input[:system]
        }

        stream_kwargs.merge!(option_mapper.map(options))

        client.public_send(
          stream_client_method,
          normalized_input[:messages],
          **stream_kwargs
        ) do |chunk|
          event = mapper.map(chunk)
          accumulator.push(event)
          block.call(event) if block && event
        end

        AssistantMessage.new(
          accumulator.result.merge(
            provider: LlmGateway::Client.provider_id_from_client(client),
            api: stream_api_name
          )
        )
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

      def stream_client_method
        :stream
      end

      def stream_api_name
        case self
        when LlmGateway::Adapters::Claude::MessagesAdapter,
             LlmGateway::Adapters::ClaudeCode::MessagesAdapter
          "messages"
        when LlmGateway::Adapters::OpenAi::ChatCompletionsAdapter,
             LlmGateway::Adapters::Groq::ChatCompletionsAdapter
          "completions"
        when LlmGateway::Adapters::OpenAi::ResponsesAdapter
          "responses"
        else
          self.class.name.split("::").last.gsub(/Adapter$/, "").downcase
        end
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
