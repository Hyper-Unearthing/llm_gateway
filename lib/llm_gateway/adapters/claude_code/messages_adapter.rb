# frozen_string_literal: true

require_relative "../adapter"
require_relative "../anthropic_option_mapper"
require_relative "input_mapper"
require_relative "output_mapper"
require_relative "../claude/output_mapper"
require_relative "../claude/stream_mapper"

module LlmGateway
  module Adapters
    module ClaudeCode
      class MessagesAdapter < Adapter
        def initialize(client)
          super(
            client,
            input_mapper: InputMapper,
            output_mapper: OutputMapper,
            file_output_mapper: Claude::FileOutputMapper,
            option_mapper: AnthropicOptionMapper,
            client_method: :chat,
            stream_mapper: Claude::StreamMapper
          )
        end
      end
    end
  end
end
