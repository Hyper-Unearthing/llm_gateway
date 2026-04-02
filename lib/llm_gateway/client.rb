# frozen_string_literal: true

module LlmGateway
  class Client
    def self.chat(model, message, tools: nil, system: nil, api_key: nil, refresh_token: nil, expires_at: nil, **options)
      adapter = build_adapter_from_model(model, api_key: api_key, refresh_token: refresh_token, expires_at: expires_at)
      adapter.chat(message, tools: tools, system: system, **options)
    end

    def self.responses(model, message, tools: nil, system: nil, api_key: nil, **options)
      adapter = build_adapter_from_model(model, api_key: api_key, api: "responses")
      adapter.chat(message, tools: tools, system: system, **options)
    end

    def self.build_client(provider, api_key:, model: "none")
      adapter = LlmGateway.build_provider(
        provider: provider,
        api_key: api_key,
        model_key: model
      )
      adapter.client
    end

    def self.upload_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      adapter = LlmGateway.build_provider(
        provider: provider,
        api_key: api_key
      )
      result = adapter.client.upload_file(*kwargs.values)
      adapter.file_output_mapper.map(result)
    end

    def self.download_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      adapter = LlmGateway.build_provider(
        provider: provider,
        api_key: api_key
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

      if model.start_with?("claude_code/")
        LlmGateway.build_provider(
          provider: "anthropic_oauth_messages",
          model_key: model,
          access_token: api_key,
          refresh_token: refresh_token,
          expires_at: expires_at
        )
      elsif api == "responses"
        config = {
          provider: "#{provider}_apikey_responses",
          model_key: model
        }
        config[:api_key] = api_key if api_key
        LlmGateway.build_provider(config)
      else
        provider_key = case provider
        when "anthropic" then "anthropic_apikey_messages"
        when "openai" then "openai_apikey_completions"
        when "groq" then "groq_apikey_completions"
        end
        config = { provider: provider_key, model_key: model }
        config[:api_key] = api_key if api_key
        LlmGateway.build_provider(config)
      end
    end

    private_class_method :build_adapter_from_model
  end
end
