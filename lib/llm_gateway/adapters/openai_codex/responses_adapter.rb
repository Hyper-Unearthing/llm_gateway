# frozen_string_literal: true

require_relative "../adapter"
require_relative "../open_ai/responses/output_mapper"
require_relative "option_mapper"
require_relative "../open_ai/responses/stream_mapper"
require_relative "../open_ai/file_output_mapper"
require_relative "input_mapper"

module LlmGateway
  module Adapters
    module OpenAiCodex
      # Adapter for LlmGateway::Clients::OpenAiCodex.
      #
      # Reuses the OpenAI Responses output/stream mappers because the Codex
      # backend speaks the same Responses API wire format.  Uses a custom
      # InputMapper that strips Codex-incompatible content blocks (unsigned
      # thinking, reasoning, summary_text) and normalises assistant content
      # directionality.  The client always streams internally, so we drive the
      # non-streaming path through +client.chat+ (which accumulates the stream
      # and returns the completed response object) and the streaming path
      # through +client.stream+.
      class ResponsesAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: OpenAiCodex::InputMapper,
            output_mapper: OpenAi::Responses::OutputMapper,
            file_output_mapper: OpenAi::FileOutputMapper,
            option_mapper: OptionMapper,
            client_method: :chat,
            stream_mapper: OpenAi::Responses::StreamMapper
          )
        end

        private

        def stream_client_method
          :stream
        end

        def stream_api_name
          "responses"
        end
      end
    end
  end
end
