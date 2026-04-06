# frozen_string_literal: true

require_relative "../open_ai/responses/option_mapper"

module LlmGateway
  module Adapters
    module OpenAiCodex
      module OptionMapper
        module_function

        def map(options)
          mapped_options = OpenAi::Responses::OptionMapper.map(options)

          # Codex endpoint currently rejects token limit parameters.
          mapped_options.delete(:max_output_tokens)
          mapped_options.delete(:max_completion_tokens)

          # Codex transport does not use retention flags in the request body.
          mapped_options.delete(:prompt_cache_retention)
          mapped_options.delete(:cacheRetention)
          mapped_options.delete(:cache_retention)

          mapped_options
        end
      end
    end
  end
end
