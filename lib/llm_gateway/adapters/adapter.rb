# frozen_string_literal: true

require_relative "structs"

module LlmGateway
  module Adapters
    class Adapter
      class << self
        def provider(value = nil)
          if value
            if instance_variable_defined?(:@provider)
              raise ArgumentError, "#{name} already declares a provider"
            end

            return @provider = value.to_s.freeze
          end

          return @provider if instance_variable_defined?(:@provider)
          return superclass.provider if superclass.respond_to?(:provider)

          raise ArgumentError, "#{name} does not declare a provider"
        end

        def client_class(value = nil)
          if value
            if instance_variable_defined?(:@client_class)
              raise ArgumentError, "#{name} already declares a client_class"
            end

            return @client_class = value
          end

          return @client_class if instance_variable_defined?(:@client_class)
          return superclass.client_class if superclass.respond_to?(:client_class)

          raise ArgumentError, "#{name} does not declare a client_class"
        end

        def definition
          @definition ||= AdapterDefinition.new(self)
        end

        def supports_model?(model)
          model.provider == provider && !LlmGateway.models.find(provider: model.provider, id: model.id).nil?
        end

        def provider_model_key(model)
          model.id
        end

        def model_for_provider_model_key(provider_model_key)
          LlmGateway.models.all(provider: provider).find do |model|
            supports_model?(model) && self.provider_model_key(model).to_s == provider_model_key.to_s
          end
        end

        def resolve_model!(model)
          if model.provider != provider
            raise LlmGateway::Errors::ModelProviderMismatch,
              "Model provider #{model.provider.inspect} does not match adapter provider #{provider.inspect}"
          end

          canonical = LlmGateway.models.find(provider: model.provider, id: model.id)
          return canonical if canonical && supports_model?(canonical)

          raise LlmGateway::Errors::UnsupportedModelForAdapter,
            "Model #{model.provider}/#{model.id} is not supported by #{name}"
        end

        def build(**config)
          config = config.transform_keys(&:to_sym)
          if config.key?(:model) || config.key?(:model_key)
            raise ArgumentError, "Models are supplied to Adapter#stream, not Adapter.build"
          end

          new(client_class.new(**config))
        end
      end

      attr_reader :client

      def initialize(client)
        @client = client
      end

      def provider
        self.class.provider
      end

      def raw_stream(message, model:, tools: nil, system: nil, **options, &block)
        model = resolve_model!(model)
        provider_model_key = self.class.provider_model_key(model)
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

        model = resolve_model!(model)
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

      # Resolves a candidate to its canonical catalog definition before streaming.
      def resolve_model!(model)
        self.class.resolve_model!(model)
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
