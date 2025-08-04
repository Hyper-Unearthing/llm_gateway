# frozen_string_literal: true

require_relative "llm_gateway/utils"
require_relative "llm_gateway/version"
require_relative "llm_gateway/errors"
require_relative "llm_gateway/fluent_mapper"
require_relative "llm_gateway/base_client"
require_relative "llm_gateway/client"
require_relative "llm_gateway/prompt"
require_relative "llm_gateway/tool"

# Load adapters - order matters for inheritance
require_relative "llm_gateway/adapters/claude/client"
require_relative "llm_gateway/adapters/claude/input_mapper"
require_relative "llm_gateway/adapters/claude/output_mapper"
require_relative "llm_gateway/adapters/groq/client"
require_relative "llm_gateway/adapters/groq/input_mapper"
require_relative "llm_gateway/adapters/groq/output_mapper"
require_relative "llm_gateway/adapters/open_ai/client"
require_relative "llm_gateway/adapters/open_ai/input_mapper"
require_relative "llm_gateway/adapters/open_ai/output_mapper"

module LlmGateway
  class Error < StandardError; end
end
