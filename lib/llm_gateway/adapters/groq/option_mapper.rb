# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Groq
      module OptionMapper
        module_function

        def map(options)
          mapped_options = options.dup
          mapped_options[:temperature] ||= 0
          mapped_options[:max_completion_tokens] ||= 20480
          mapped_options[:response_format] = normalize_response_format(mapped_options[:response_format] || "text")
          mapped_options
        end

        def normalize_response_format(response_format)
          if response_format.is_a?(String)
            { type: response_format }
          else
            response_format
          end
        end
      end
    end
  end
end
