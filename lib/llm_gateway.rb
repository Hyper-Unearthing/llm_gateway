# frozen_string_literal: true

require_relative "llm_gateway/utils"
require_relative "llm_gateway/version"
require_relative "llm_gateway/errors"
require_relative "llm_gateway/base_client"
require_relative "llm_gateway/client"
require_relative "llm_gateway/prompt"
require_relative "llm_gateway/tool"

# Load clients - order matters for inheritance
require_relative "llm_gateway/clients/anthropic"
require_relative "llm_gateway/clients/claude_code/oauth_flow"
require_relative "llm_gateway/clients/claude_code/token_manager"
require_relative "llm_gateway/clients/openai"
require_relative "llm_gateway/clients/openai_codex/oauth_flow"
require_relative "llm_gateway/clients/openai_codex/token_manager"
require_relative "llm_gateway/clients/groq"

# Load adapters
require_relative "llm_gateway/adapters/option_mapper"
require_relative "llm_gateway/adapters/anthropic_option_mapper"
require_relative "llm_gateway/adapters/structs"

require_relative "llm_gateway/adapters/anthropic/input_mapper"
require_relative "llm_gateway/adapters/anthropic/output_mapper"
require_relative "llm_gateway/adapters/openai/file_output_mapper"
require_relative "llm_gateway/adapters/openai/prompt_cache_option_mapper"
require_relative "llm_gateway/adapters/openai/chat_completions/input_mapper"
require_relative "llm_gateway/adapters/openai/chat_completions/output_mapper"
require_relative "llm_gateway/adapters/openai/chat_completions/option_mapper"
require_relative "llm_gateway/adapters/openai/file_output_mapper"
require_relative "llm_gateway/adapters/openai/responses/input_mapper"
require_relative "llm_gateway/adapters/openai/responses/output_mapper"
require_relative "llm_gateway/adapters/openai/responses/option_mapper"

# Load adapter classes
require_relative "llm_gateway/adapters/adapter"
require_relative "llm_gateway/adapters/anthropic/messages_adapter"
require_relative "llm_gateway/adapters/openai/chat_completions_adapter"
require_relative "llm_gateway/adapters/openai/responses_adapter"
require_relative "llm_gateway/adapters/openai_codex/responses_adapter"
require_relative "llm_gateway/adapters/groq/chat_completions_adapter"

# Load provider registry
require_relative "llm_gateway/provider_registry"

module LlmGateway
  class Error < StandardError; end

  # Direction constants for message mappers
  DIRECTION_IN = :in
  DIRECTION_OUT = :out

  # Backward-compatible aliases for renamed clients/adapters
  module Clients
    Claude = Anthropic
    OpenAi = OpenAI
  end

  module Adapters
    module Claude
      Client = LlmGateway::Clients::Anthropic
      MessagesAdapter = LlmGateway::Adapters::Anthropic::MessagesAdapter
      InputMapper = LlmGateway::Adapters::Anthropic::InputMapper
      OutputMapper = LlmGateway::Adapters::Anthropic::OutputMapper
      StreamMapper = LlmGateway::Adapters::Anthropic::StreamMapper
      BidirectionalMessageMapper = LlmGateway::Adapters::Anthropic::BidirectionalMessageMapper
      FileOutputMapper = LlmGateway::Adapters::Anthropic::FileOutputMapper
    end

    module Anthropic
      Client = LlmGateway::Clients::Anthropic
    end

    module OpenAI
      Client = LlmGateway::Clients::OpenAI
    end

    module OpenAi
      Client = LlmGateway::Clients::OpenAI
      ChatCompletionsAdapter = LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter
      ResponsesAdapter = LlmGateway::Adapters::OpenAI::ResponsesAdapter
      PromptCacheOptionMapper = LlmGateway::Adapters::OpenAI::PromptCacheOptionMapper
      FileOutputMapper = LlmGateway::Adapters::OpenAI::FileOutputMapper
      ChatCompletions = LlmGateway::Adapters::OpenAI::ChatCompletions
      Responses = LlmGateway::Adapters::OpenAI::Responses
    end

    module OpenAICodex
      Client = LlmGateway::Clients::OpenAI
    end

    module OpenAiCodex
      Client = LlmGateway::Clients::OpenAI
      ResponsesAdapter = LlmGateway::Adapters::OpenAICodex::ResponsesAdapter
      InputMapper = LlmGateway::Adapters::OpenAICodex::InputMapper
      OptionMapper = LlmGateway::Adapters::OpenAICodex::OptionMapper
    end

    module Groq
      Client = LlmGateway::Clients::Groq
    end
  end

  def self.build_provider(config)
    config = config.transform_keys(&:to_sym)
    provider_name = config.delete(:provider)
    entry = ProviderRegistry.resolve(provider_name)

    client = entry[:client].new(**config)
    entry[:adapter].new(client)
  end

  def self.configure(configs)
    @configured_clients ||= {}

    configs.each do |entry|
      name = entry[:name] || entry["name"]
      config = entry[:config] || entry["config"]

      raise ArgumentError, "Each config entry must have a :name" unless name

      client = build_provider(config)
      @configured_clients[name.to_sym] = client

      define_singleton_method(name.to_sym) { @configured_clients[name.to_sym] }
    end
  end

  def self.configured_clients
    @configured_clients ||= {}
  end

  def self.reset_configuration!
    @configured_clients&.each_key do |name|
      singleton_class.remove_method(name) if respond_to?(name)
    end
    @configured_clients = {}
  end

  # Register built-in providers (canonical keys)
  ProviderRegistry.register("anthropic_messages",
    client: Clients::Anthropic,
    adapter: Adapters::Anthropic::MessagesAdapter)

  ProviderRegistry.register("openai_completions",
    client: Clients::OpenAI,
    adapter: Adapters::OpenAI::ChatCompletionsAdapter)

  ProviderRegistry.register("openai_responses",
    client: Clients::OpenAI,
    adapter: Adapters::OpenAI::ResponsesAdapter)

  ProviderRegistry.register("groq_completions",
    client: Clients::Groq,
    adapter: Adapters::Groq::ChatCompletionsAdapter)

  ProviderRegistry.register("openai_codex",
    client: Clients::OpenAI,
    adapter: Adapters::OpenAICodex::ResponsesAdapter)

  # Backward-compatible aliases (deprecated)
  ProviderRegistry.register("anthropic_apikey_messages",
    client: Clients::Anthropic,
    adapter: Adapters::Anthropic::MessagesAdapter)

  ProviderRegistry.register("openai_apikey_completions",
    client: Clients::OpenAI,
    adapter: Adapters::OpenAI::ChatCompletionsAdapter)

  ProviderRegistry.register("openai_apikey_responses",
    client: Clients::OpenAI,
    adapter: Adapters::OpenAI::ResponsesAdapter)

  ProviderRegistry.register("groq_apikey_completions",
    client: Clients::Groq,
    adapter: Adapters::Groq::ChatCompletionsAdapter)

  ProviderRegistry.register("openai_oauth_codex",
    client: Clients::OpenAI,
    adapter: Adapters::OpenAICodex::ResponsesAdapter)
end
