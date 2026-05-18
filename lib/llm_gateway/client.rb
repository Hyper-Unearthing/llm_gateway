# frozen_string_literal: true


module LlmGateway
  class Client
    def self.provider_id_from_client(client)
      case client
      when LlmGateway::Clients::Anthropic
        "anthropic"
      when LlmGateway::Clients::OpenAI
        "openai"
      when LlmGateway::Clients::Groq
        "groq"
      end
    end

    def self.upload_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      adapter = LlmGateway.build_provider(
        provider: provider,
        api_key: api_key
      )
      adapter.upload_file(**kwargs)
    end

    def self.download_file(provider, **kwargs)
      api_key = kwargs.delete(:api_key)
      adapter = LlmGateway.build_provider(
        provider: provider,
        api_key: api_key
      )
      adapter.download_file(**kwargs)
    end
  end
end
