# frozen_string_literal: true

require_relative "../decisions_adapter"

module LlmGateway
  module Adapters
    module TypeSafe
      class DecisionsAdapter < LlmGateway::Adapters::DecisionsAdapter
        provider "typesafe"
        client_class LlmGateway::Clients::TypeSafe
      end

      module Decisions
        extend DefinitionFacade
        define_adapter(DecisionsAdapter)
      end
    end
  end
end
