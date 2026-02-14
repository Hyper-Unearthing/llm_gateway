# frozen_string_literal: true

module LlmGateway
  class Client
    def self.chat(model, message, response_format: "text", tools: nil, system: nil, api_key: nil, refresh_token: nil, expires_at: nil)
      adapter = build_adapter_from_model(model, api_key: api_key, refresh_token: refresh_token, expires_at: expires_at)
      adapter.chat(message, response_format: response_format, tools: tools, system: system)
    end

    def self.responses(model, message, response_format: "text", tools: nil, system: nil, api_key: nil)
      adapter = build_adapter_from_model(model, api_key: api_key, api: "responses")
      adapter.chat(message, response_format: response_format, tools: tools, system: system)
    end

    def self.build_client(provider, api_key:, model: "none")
      adapter = ClientBuilder.build(
        provider: provider,
        type: "api_key",
        key: api_key,
        model: model
      )
      adapter.client
    end

    def self.upload_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      adapter = ClientBuilder.build(
        provider: provider,
        type: "api_key",
        key: api_key
      )
      result = adapter.client.upload_file(*kwargs.values)
      adapter.file_output_mapper.map(result)
    end

    def self.download_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      adapter = ClientBuilder.build(
        provider: provider,
        type: "api_key",
        key: api_key
      )
      result = adapter.client.download_file(*kwargs.values)
      adapter.file_output_mapper.map(result)
    end

    def self.provider_from_model(model)
      return "anthropic" if model.start_with?("claude_code/")
      return "anthropic" if model.start_with?("claude")
      return "groq" if model.start_with?("llama")
      return "openai" if model.start_with?("gpt") ||
                         model.start_with?("o4-") ||
                         model.start_with?("openai")

      raise LlmGateway::Errors::UnsupportedModel, model
    end

    def self.provider_id_from_client(client)
      case client
      when LlmGateway::Clients::ClaudeCode
        "claude_code"
      when LlmGateway::Clients::Claude
        "anthropic"
      when LlmGateway::Clients::OpenAi
        "openai"
      when LlmGateway::Clients::Groq
        "groq"
      else
        raise LlmGateway::Errors::UnsupportedProvider, client.class.name
      end
    end

    # --- private helpers ---

    def self.build_adapter_from_model(model, api_key: nil, refresh_token: nil, expires_at: nil, api: nil)
      provider = provider_from_model(model)
      config = { provider: provider, model: model }

      if model.start_with?("claude_code/")
        config[:type] = "oauth"
        config[:accessToken] = api_key
        config[:refreshToken] = refresh_token
        config[:expiresAt] = expires_at
      else
        config[:type] = "api_key"
        config[:key] = api_key
      end

      config[:api] = api if api

      ClientBuilder.build(config)
    end

    private_class_method :build_adapter_from_model
  end
end
