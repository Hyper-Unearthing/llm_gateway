# frozen_string_literal: true

require_relative "../open_ai/responses/option_mapper"

module LlmGateway
  module Adapters
    module OpenAiCodex
      module OptionMapper
        module_function

        def map(options)
          mapped_options = OpenAi::Responses::OptionMapper.map(options)
          mapped_options[:max_completion_tokens] ||= 20480
          mapped_options
        end
      end
    end
  end
end
