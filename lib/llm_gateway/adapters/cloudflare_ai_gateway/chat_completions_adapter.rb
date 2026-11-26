# frozen_string_literal: true

require_relative "../chat_completions_adapter"
require_relative "option_mapper"

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      class ChatCompletionsAdapter < LlmGateway::Adapters::ChatCompletionsAdapter
        provider "cloudflare-ai-gateway"
        client_class LlmGateway::Clients::CloudflareAIGateway

        def self.system_role = "system"
        def self.option_mapper = CloudflareAIGateway::OptionMapper
      end

      module ChatCompletions
        extend DefinitionFacade
        define_adapter ChatCompletionsAdapter
      end
    end
  end
end
