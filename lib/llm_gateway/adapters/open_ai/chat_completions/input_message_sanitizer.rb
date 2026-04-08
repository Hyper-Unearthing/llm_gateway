# frozen_string_literal: true

require_relative "../../input_message_sanitizer"

module LlmGateway
  module Adapters
    module OpenAi
      module ChatCompletions
        class InputMessageSanitizer < LlmGateway::Adapters::InputMessageSanitizer
          def self.sanitize(messages, target_provider:, target_api:, target_model:)
            sanitized = super
            normalize_tool_call_ids(sanitized, target_provider: target_provider)
          end

          def self.normalize_tool_call_ids(messages, target_provider:)
            return messages unless messages.is_a?(Array)

            id_map = {}

            messages.map do |message|
              next message unless message.is_a?(Hash) && message[:content].is_a?(Array)

              content = message[:content].map do |block|
                next block unless block.is_a?(Hash)

                type = block[:type] || block["type"]

                case type
                when "tool_use", "function"
                  original_id = block[:id] || block["id"]
                  normalized_id = normalize_tool_call_id(original_id, target_provider: target_provider)
                  id_map[original_id] = normalized_id if original_id && normalized_id
                  block.merge(id: normalized_id)
                when "tool_result"
                  original_tool_use_id = block[:tool_use_id] || block["tool_use_id"]
                  normalized_tool_use_id = id_map[original_tool_use_id] || normalize_tool_call_id(original_tool_use_id, target_provider: target_provider)
                  block.merge(tool_use_id: normalized_tool_use_id)
                else
                  block
                end
              end

              message.merge(content: content)
            end
          end

          def self.normalize_tool_call_id(id, target_provider:)
            return id unless id.is_a?(String)

            if id.include?("|")
              call_id = id.split("|", 2).first
              call_id.gsub(/[^a-zA-Z0-9_-]/, "_")[0, 40]
            elsif target_provider == "openai"
              id[0, 40]
            else
              id
            end
          end

          private_class_method :normalize_tool_call_ids, :normalize_tool_call_id
        end
      end
    end
  end
end
