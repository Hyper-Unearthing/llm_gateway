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

    def self.upload_file(adapter, **kwargs)
      api_key = kwargs.delete(:api_key)
      LlmGateway.build_adapter(adapter: adapter, api_key: api_key).upload_file(**kwargs)
    end

    def self.download_file(adapter, **kwargs)
      api_key = kwargs.delete(:api_key)
      LlmGateway.build_adapter(adapter: adapter, api_key: api_key).download_file(**kwargs)
    end
  end
end
