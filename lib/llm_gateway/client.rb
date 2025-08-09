# frozen_string_literal: true

module LlmGateway
  class Client
    def self.chat(model, message, response_format: "text", tools: nil, system: nil, api_key: nil)
      client_klass = client_class(model)
      client_options = { model_key: model }
      client_options[:api_key] = api_key if api_key
      client = client_klass.new(**client_options)

      input_mapper = input_mapper_for_client(client)
      normalized_input = input_mapper.map({
        messages: normalize_messages(message),
        response_format: normalize_response_format(response_format),
        tools: tools,
        system: normalize_system(system)
      })
      result = client.chat(
        normalized_input[:messages],
        response_format: normalized_input[:response_format],
        tools: normalized_input[:tools],
        system: normalized_input[:system]
      )
      result_mapper(client).map(result)
    end

    def self.build_client(provider, api_key:, model: "none")
      client_klass = client_class_by_id(provider)
      client_options = { model_key: model }
      client_options[:api_key] = api_key if api_key
      client_klass.new(**client_options)
    end

    def self.upload_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      client = build_client(provider, api_key: api_key)
      result = client.upload_file(*kwargs.values)
      file_output_mapper(client).map(result)
    end

    def self.download_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      client = build_client(provider, api_key: api_key)
      result = client.download_file(*kwargs.values)
      file_output_mapper(client).map(result)
    end

    def self.file_output_mapper(client)
      return LlmGateway::Adapters::Claude::FileOutputMapper if client.is_a?(LlmGateway::Adapters::Claude::Client)
      return LlmGateway::Adapters::OpenAi::FileOutputMapper if client.is_a?(LlmGateway::Adapters::OpenAi::Client)

      raise MissingMapperForProvider, "Client:#{client} Object:File"
    end

    def self.client_class(model)
      return LlmGateway::Adapters::Claude::Client if model.start_with?("claude")
      return LlmGateway::Adapters::Groq::Client if model.start_with?("llama")
      return LlmGateway::Adapters::OpenAi::Client if model.start_with?("gpt") ||
                                                     model.start_with?("o4-") ||
                                                     model.start_with?("openai")

      raise LlmGateway::Errors::UnsupportedModel, model
    end

    def self.client_class_by_id(provider_id)
      return LlmGateway::Adapters::Claude::Client if provider_id == ("anthropic")
      return LlmGateway::Adapters::Groq::Client if provider_id == ("groq")
      return LlmGateway::Adapters::OpenAi::Client if provider_id == ("openai")


      raise LlmGateway::Errors::UnsupportedProvider, provider_id
    end

    def self.input_mapper_for_client(client)
      return LlmGateway::Adapters::Claude::InputMapper if client.is_a?(LlmGateway::Adapters::Claude::Client)
      return LlmGateway::Adapters::OpenAi::InputMapper if client.is_a?(LlmGateway::Adapters::OpenAi::Client)

      LlmGateway::Adapters::Groq::InputMapper if client.is_a?(LlmGateway::Adapters::Groq::Client)
    end

    def self.result_mapper(client)
      return LlmGateway::Adapters::Claude::OutputMapper if client.is_a?(LlmGateway::Adapters::Claude::Client)
      return LlmGateway::Adapters::OpenAi::OutputMapper if client.is_a?(LlmGateway::Adapters::OpenAi::Client)

      LlmGateway::Adapters::Groq::OutputMapper if client.is_a?(LlmGateway::Adapters::Groq::Client)
    end

    def self.normalize_system(system)
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

    def self.normalize_messages(message)
      if message.is_a?(String)
        [ { 'role': "user", 'content': message } ]
      else
        message
      end
    end

    def self.normalize_response_format(response_format)
      if response_format.is_a?(String)
        { type: response_format }
      else
        response_format
      end
    end
  end
end
