# frozen_string_literal: true

module LlmGateway
  class Client
    def self.provider_configs
      @provider_configs ||= {
        anthropic: {
          input_mapper: LlmGateway::Adapters::Claude::InputMapper,
          output_mapper: LlmGateway::Adapters::Claude::OutputMapper,
          client: LlmGateway::Adapters::Claude::Client,
          file_output_mapper: LlmGateway::Adapters::Claude::FileOutputMapper
        },
        claude_code: {
          input_mapper: LlmGateway::Adapters::ClaudeCode::InputMapper,
          output_mapper: LlmGateway::Adapters::ClaudeCode::OutputMapper,
          client: LlmGateway::Adapters::ClaudeCode::Client,
          file_output_mapper: LlmGateway::Adapters::Claude::FileOutputMapper
        },
        openai: {
          input_mapper: LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper,
          output_mapper: LlmGateway::Adapters::OpenAi::ChatCompletions::OutputMapper,
          client: LlmGateway::Adapters::OpenAi::Client,
          file_output_mapper: LlmGateway::Adapters::OpenAi::FileOutputMapper
        },
        openai_responses: {
          input_mapper: LlmGateway::Adapters::OpenAi::Responses::InputMapper,
          output_mapper: LlmGateway::Adapters::OpenAi::Responses::OutputMapper,
          client: LlmGateway::Adapters::OpenAi::Client,
          file_output_mapper: LlmGateway::Adapters::OpenAi::FileOutputMapper
        },
        groq: {
          input_mapper: LlmGateway::Adapters::Groq::InputMapper,
          output_mapper: LlmGateway::Adapters::Groq::OutputMapper,
          client: LlmGateway::Adapters::Groq::Client,
          file_output_mapper: nil
        }
      }.freeze
    end

    def self.get_provider_config(provider_id)
      provider_configs[provider_id.to_sym] || raise(LlmGateway::Errors::UnsupportedProvider, provider_id)
    end

    def self.chat(model, message, response_format: "text", tools: nil, system: nil, api_key: nil, refresh_token: nil, expires_at: nil)
      provider = provider_from_model(model)
      config = get_provider_config(provider)
      client_options = { model_key: model }
      client_options[:api_key] = api_key if api_key
      client_options[:refresh_token] = refresh_token if refresh_token
      client_options[:expires_at] = expires_at if expires_at
      client = config[:client].new(**client_options)

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


    def self.responses(model, message, response_format: "text", tools: nil, system: nil, api_key: nil)
      provider = provider_from_model(model)
      actual_model = model
      config = provider == "openai" ? get_provider_config("openai_responses") : get_provider_config(provider)
      client_options = { model_key: actual_model }
      client_options[:api_key] = api_key if api_key
      client = config[:client].new(**client_options)
      input_mapper = config[:input_mapper]
      normalized_input = input_mapper.map({
        messages: normalize_messages(message),
        response_format: normalize_response_format(response_format),
        tools: tools,
        system: normalize_system(system)
      })
      method = provider == "openai" ? "responses" : "chat"
      result = client.send(method,
        normalized_input[:messages],
        response_format: normalized_input[:response_format],
        tools: normalized_input[:tools],
        system: normalized_input[:system]
      )
      config[:output_mapper].map(result)
    end

    def self.build_client(provider, api_key:, model: "none")
      config = get_provider_config(provider)
      client_options = { model_key: model }
      client_options[:api_key] = api_key if api_key
      config[:client].new(**client_options)
    end

    def self.upload_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      client = build_client(provider, api_key: api_key)
      result = client.upload_file(*kwargs.values)
      config = get_provider_config(provider)
      config[:file_output_mapper].map(result)
    end

    def self.download_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      client = build_client(provider, api_key: api_key)
      result = client.download_file(*kwargs.values)
      config = get_provider_config(provider)
      config[:file_output_mapper].map(result)
    end
    #         actual_model = model.split("/", 2)[1]
    def self.provider_from_model(model)
      return "claude_code" if model.start_with?("claude_code/")
      return "anthropic" if model.start_with?("claude")
      return "groq" if model.start_with?("llama")
      return "openai" if model.start_with?("gpt") ||
                         model.start_with?("o4-") ||
                         model.start_with?("openai")

      raise LlmGateway::Errors::UnsupportedModel, model
    end


    def self.input_mapper_for_client(client)
      config = get_provider_config_by_client(client)
      config[:input_mapper]
    end

    def self.result_mapper(client)
      config = get_provider_config_by_client(client)
      config[:output_mapper]
    end

    def self.provider_id_from_client(client)
      case client
      when LlmGateway::Adapters::ClaudeCode::Client
        "claude_code"
      when LlmGateway::Adapters::Claude::Client
        "anthropic"
      when LlmGateway::Adapters::OpenAi::Client
        "openai"
      when LlmGateway::Adapters::Groq::Client
        "groq"
      else
        raise LlmGateway::Errors::UnsupportedProvider, client.class.name
      end
    end

    def self.get_provider_config_by_client(client)
      provider_id = provider_id_from_client(client)
      get_provider_config(provider_id)
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
