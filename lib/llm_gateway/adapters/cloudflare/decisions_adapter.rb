# frozen_string_literal: true

require_relative "../decisions_adapter"

module LlmGateway
  module Adapters
    module Cloudflare
      class DecisionsAdapter < LlmGateway::Adapters::DecisionsAdapter
        provider "cloudflare"
        client_class LlmGateway::Clients::Cloudflare
      end

      module Decisions
        extend DefinitionFacade
        define_adapter(DecisionsAdapter)
      end
    end
  end
end
