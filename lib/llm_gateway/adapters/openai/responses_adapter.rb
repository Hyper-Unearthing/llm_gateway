# frozen_string_literal: true

require_relative "../adapter"
require_relative "acts_like_responses"
require_relative "../input_message_sanitizer"
require_relative "responses/input_mapper"
require_relative "responses/option_mapper"
require_relative "file_output_mapper"
require_relative "responses/stream_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      class ResponsesAdapter < Adapter
        provider "openai"
        client_class LlmGateway::Clients::OpenAI

        include ActsLikeOpenAIResponses
      end

      Responses.extend(DefinitionFacade)
      Responses.define_adapter(ResponsesAdapter)
    end
  end
end
