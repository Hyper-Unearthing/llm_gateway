# frozen_string_literal: true

require_relative "llm_gateway/utils"
require_relative "llm_gateway/version"
require_relative "llm_gateway/errors"
require_relative "llm_gateway/base_client"
require_relative "llm_gateway/client"
require_relative "llm_gateway/prompt"
require_relative "llm_gateway/tool"

# Load clients - order matters for inheritance
require_relative "llm_gateway/clients/claude"
require_relative "llm_gateway/clients/claude_code"
require_relative "llm_gateway/clients/open_ai"
require_relative "llm_gateway/clients/groq"

# Load adapters
require_relative "llm_gateway/adapters/claude/input_mapper"
require_relative "llm_gateway/adapters/claude/output_mapper"
require_relative "llm_gateway/adapters/claude_code/input_mapper"
require_relative "llm_gateway/adapters/claude_code/output_mapper"
require_relative "llm_gateway/adapters/open_ai/file_output_mapper"
require_relative "llm_gateway/adapters/open_ai/chat_completions/input_mapper"
require_relative "llm_gateway/adapters/open_ai/chat_completions/output_mapper"
require_relative "llm_gateway/adapters/groq/input_mapper"
require_relative "llm_gateway/adapters/groq/output_mapper"
require_relative "llm_gateway/adapters/open_ai/file_output_mapper"
require_relative "llm_gateway/adapters/open_ai/responses/input_mapper"
require_relative "llm_gateway/adapters/open_ai/responses/output_mapper"

# Load adapter classes
require_relative "llm_gateway/adapters/adapter"
require_relative "llm_gateway/adapters/claude/messages_adapter"
require_relative "llm_gateway/adapters/claude_code/messages_adapter"
require_relative "llm_gateway/adapters/open_ai/chat_completions_adapter"
require_relative "llm_gateway/adapters/open_ai/responses_adapter"
require_relative "llm_gateway/adapters/groq/chat_completions_adapter"

# Load builder
require_relative "llm_gateway/client_builder"

module LlmGateway
  class Error < StandardError; end

  # Direction constants for message mappers
  DIRECTION_IN = :in
  DIRECTION_OUT = :out

  # Backward-compatible aliases for clients that moved from Adapters to Clients
  module Adapters
    module Claude
      Client = LlmGateway::Clients::Claude
    end

    module ClaudeCode
      Client = LlmGateway::Clients::ClaudeCode
    end

    module OpenAi
      Client = LlmGateway::Clients::OpenAi
    end

    module Groq
      Client = LlmGateway::Clients::Groq
    end
  end
end
