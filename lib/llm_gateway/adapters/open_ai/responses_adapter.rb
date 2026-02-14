# frozen_string_literal: true

require_relative "../adapter"
require_relative "responses/input_mapper"
require_relative "responses/output_mapper"
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
            file_output_mapper: FileOutputMapper
          )
        end

        def chat(message, response_format: "text", tools: nil, system: nil)
          normalized_input = input_mapper.map({
            messages: normalize_messages(message),
            response_format: normalize_response_format(response_format),
            tools: tools,
            system: normalize_system(system)
          })
          result = client.responses(
            normalized_input[:messages],
            response_format: normalized_input[:response_format],
            tools: normalized_input[:tools],
            system: normalized_input[:system]
          )
          output_mapper.map(result)
        end
      end
    end
  end
end
