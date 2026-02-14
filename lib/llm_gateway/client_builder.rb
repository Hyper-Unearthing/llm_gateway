# frozen_string_literal: true

module LlmGateway
  class ClientBuilder
    PROVIDERS = {
      "groq" => {
        client: Clients::Groq,
        default_adapter: Adapters::Groq::ChatCompletionsAdapter
      },
      "anthropic" => {
        "api_key" => {
          client: Clients::Claude,
          default_adapter: Adapters::Claude::MessagesAdapter
        },
        "oauth" => {
          client: Clients::ClaudeCode,
          default_adapter: Adapters::ClaudeCode::MessagesAdapter
        }
      },
      "openai" => {
        client: Clients::OpenAi,
        default_adapter: Adapters::OpenAi::ChatCompletionsAdapter,
        adapters: {
          "completions" => Adapters::OpenAi::ChatCompletionsAdapter,
          "responses" => Adapters::OpenAi::ResponsesAdapter
        }
      }
    }.freeze

    def self.build(config)
      new(config).build
    end

    def initialize(config)
      @config = config
    end

    def build
      provider = @config[:provider] || @config["provider"]
      type = @config[:type] || @config["type"]
      api = @config[:api] || @config["api"]

      config = resolve_provider_config(provider, type)
      client = build_client(config[:client], type)
      adapter_class = resolve_adapter(config, api)

      adapter_class.new(client)
    end

    private

    def resolve_provider_config(provider, type)
      provider_config = PROVIDERS[provider]
      raise Errors::UnsupportedProvider, "Unknown provider: #{provider}" unless provider_config

      if provider == "anthropic"
        config = provider_config[type]
        raise Errors::UnsupportedProvider, "Unknown auth type '#{type}' for provider '#{provider}'" unless config
        config
      else
        provider_config
      end
    end

    def build_client(client_class, type)
      model = @config[:model] || @config["model"]

      case client_class.name
      when Clients::ClaudeCode.name
        opts = {
          access_token: @config[:accessToken] || @config["accessToken"],
          refresh_token: @config[:refreshToken] || @config["refreshToken"],
          expires_at: @config[:expiresAt] || @config["expiresAt"]
        }
        opts[:model_key] = model if model
        client_class.new(**opts)
      else
        opts = {}
        key = @config[:key] || @config["key"]
        opts[:api_key] = key if key
        opts[:model_key] = model if model
        client_class.new(**opts)
      end
    end

    def resolve_adapter(config, api)
      return config[:default_adapter] if api.nil?

      adapters = config[:adapters]
      return config[:default_adapter] unless adapters

      adapters[api] || config[:default_adapter]
    end
  end
end
