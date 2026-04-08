# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAI
      module PromptCacheOptionMapper
        def self.included(base)
          base.extend(self)
        end

        def map_cache_key!(mapped_options)
          cache_key = mapped_options.delete(:cache_key)
          mapped_options.delete(:prompt_cache_key)
          mapped_options[:prompt_cache_key] = cache_key unless cache_key.nil?
        end

        def map_prompt_cache_retention!(mapped_options)
          retention = mapped_options.delete(:cache_retention)
          mapped_options.delete(:prompt_cache_retention)
          retention ||= "short" if mapped_options.key?(:prompt_cache_key)

          case retention&.to_s
          when nil
            nil
          when "short"
            mapped_options[:prompt_cache_retention] = "in_memory"
          when "long"
            mapped_options[:prompt_cache_retention] = "24h"
          when "none"
            mapped_options.delete(:prompt_cache_key)
          else
            raise ArgumentError,
              "Invalid cache_retention '#{retention}'. Use 'short', 'long', or 'none'."
          end
        end
      end
    end
  end
end
