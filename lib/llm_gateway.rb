# frozen_string_literal: true

require_relative "llm_gateway/utils"
require_relative "llm_gateway/version"
require_relative "llm_gateway/errors"
require_relative "llm_gateway/base_client"
require_relative "llm_gateway/tool"
require_relative "llm_gateway/prompt"
require_relative "llm_gateway/agents/event"
require_relative "llm_gateway/agents/in_memory_session_manager"
require_relative "llm_gateway/agents/file_session_manager"
require_relative "llm_gateway/agents/harness"

# Load clients - order matters for inheritance
require_relative "llm_gateway/clients/anthropic"
require_relative "llm_gateway/clients/claude_code/oauth_flow"
require_relative "llm_gateway/clients/claude_code/token_manager"
require_relative "llm_gateway/clients/openai"
require_relative "llm_gateway/clients/openai_codex/oauth_flow"
require_relative "llm_gateway/clients/openai_codex/token_manager"
require_relative "llm_gateway/clients/groq"

# Load adapters
require_relative "llm_gateway/adapter_definition"
require_relative "llm_gateway/adapters/option_mapper"
require_relative "llm_gateway/adapters/anthropic_option_mapper"
require_relative "llm_gateway/adapters/structs"
require_relative "llm_gateway/adapters/stream_mapper"

require_relative "llm_gateway/adapters/anthropic/input_mapper"
require_relative "llm_gateway/adapters/anthropic/output_mapper"
require_relative "llm_gateway/adapters/openai/file_output_mapper"
require_relative "llm_gateway/adapters/openai/prompt_cache_option_mapper"
require_relative "llm_gateway/adapters/openai/chat_completions/input_mapper"
require_relative "llm_gateway/adapters/openai/chat_completions/option_mapper"
require_relative "llm_gateway/adapters/openai/chat_completions/stream_mapper"
require_relative "llm_gateway/adapters/openai/file_output_mapper"
require_relative "llm_gateway/adapters/openai/responses/input_mapper"
require_relative "llm_gateway/adapters/openai/responses/option_mapper"

# Load adapter classes
require_relative "llm_gateway/adapters/adapter"
require_relative "llm_gateway/adapters/anthropic/messages_adapter"
require_relative "llm_gateway/adapters/openai/chat_completions_adapter"
require_relative "llm_gateway/adapters/openai/responses_adapter"
require_relative "llm_gateway/adapters/openai_codex/responses_adapter"
require_relative "llm_gateway/adapters/groq/chat_completions_adapter"

# Load the provider-level model catalog and proxy transport
require_relative "llm_gateway/models"
require_relative "llm_gateway/proxy/protocol"
require_relative "llm_gateway/proxy/client"
require_relative "llm_gateway/proxy/adapter"
require_relative "llm_gateway/proxy/server"

module LlmGateway
  class Error < StandardError; end

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
      StreamMapper = LlmGateway::Adapters::Anthropic::StreamMapper
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
end
