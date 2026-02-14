# frozen_string_literal: true

require_relative "../adapter"
require_relative "input_mapper"
require_relative "output_mapper"
require_relative "../claude/output_mapper"

module LlmGateway
  module Adapters
    module ClaudeCode
      class MessagesAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: InputMapper,
            output_mapper: OutputMapper,
            file_output_mapper: Claude::FileOutputMapper
          )
        end
      end
    end
  end
end
