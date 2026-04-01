# frozen_string_literal: true

require_relative "../adapter"
require_relative "responses/input_mapper"
require_relative "responses/output_mapper"
require_relative "responses/option_mapper"
require_relative "file_output_mapper"

module LlmGateway
  module Adapters
    module OpenAi
      class ResponsesAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: Responses::InputMapper,
            output_mapper: Responses::OutputMapper,
            file_output_mapper: FileOutputMapper,
            option_mapper: Responses::OptionMapper,
            client_method: :responses
          )
        end
      end
    end
  end
end
