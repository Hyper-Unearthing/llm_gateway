# frozen_string_literal: true

require_relative "../anthropic_option_mapper"

module LlmGateway
  module Adapters
    module ClaudeCode
      module OptionMapper
        module_function

        def map(options)
          mapped_options = AnthropicOptionMapper.map(options)

          max_completion_tokens = mapped_options.delete(:max_completion_tokens)
          mapped_options[:max_tokens] = max_completion_tokens || mapped_options[:max_tokens] || 20480

          mapped_options
        end
      end
    end
  end
end
