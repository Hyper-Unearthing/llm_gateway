# frozen_string_literal: true

module LlmGateway
  module Adapters
    module CloudflareAIGateway
      # Public model IDs stay in the catalog namespace. Wire IDs and protocols
      # are route-specific; never interpolate catalog URLs into transport URLs.
      module Routes
        Route = Struct.new(:transport, :model, keyword_init: true) do
          def messages? = transport != :rest_completions
        end

        module_function

        def for(model)
          author = model.id.split("/", 2).first
          if author == "anthropic"
            canonical = model.routing[:canonical_model_id] || model.id.tr(".", "-")
            Route.new(transport: :anthropic_native, model: canonical.delete_prefix("anthropic/")).freeze
          elsif author == "minimax"
            # Cloudflare's Chat Completions translation currently breaks tools
            # for MiniMax. Its REST Messages route passes full tool round trips.
            Route.new(transport: :rest_messages, model: model.id).freeze
          else
            Route.new(transport: :rest_completions, model: model.id).freeze
          end
        end
      end
    end
  end
end
