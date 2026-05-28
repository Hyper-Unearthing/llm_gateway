# frozen_string_literal: true

require "json"

module LlmGateway
  module Adapters
    class InputMessageSanitizer
      def self.sanitize(messages, target_provider:, target_api:, target_model:)
        return messages unless messages.is_a?(Array)

        sanitized = messages.map do |message|
          sanitize_message(
            message,
            target_provider: target_provider,
            target_api: target_api,
            target_model: target_model
          )
        end

        relocate_assistant_tool_results(sanitized)
      end

      def self.sanitize_message(message, target_provider:, target_api:, target_model:)
        return message unless message.is_a?(Hash)

        role = message[:role] || message["role"]
        content = message[:content] || message["content"]
        return message unless role == "assistant" && content.is_a?(Array)
        return message unless message_metadata_present?(message)

        same_model_replay = same_model_replay?(message, target_provider:, target_api:, target_model:)
        same_provider_api_replay = same_provider_api_replay?(message, target_provider:, target_api:)

        sanitized_content = content.each_with_object([]) do |block, acc|
          sanitized = sanitize_content_block(
            block,
            same_model_replay: same_model_replay,
            same_provider_api_replay: same_provider_api_replay
          )
          next if sanitized.nil?

          if sanitized.is_a?(Array)
            acc.concat(sanitized)
          else
            acc << sanitized
          end
        end

        message.merge(content: sanitized_content)
      end

      def self.sanitize_content_block(block, same_model_replay:, same_provider_api_replay:)
        return block unless block.is_a?(Hash)

        type = block[:type] || block["type"]

        if type == "server_tool_use"
          return normalize_server_tool_use_for_replay(block) if same_provider_api_replay

          return convert_server_tool_use_to_tool_use(block)
        end

        if type == "server_tool_result"
          return block if same_provider_api_replay

          return convert_server_tool_result_to_tool_result(block)
        end

        return block unless %w[thinking reasoning].include?(type)
        return block if same_model_replay

        text = extract_reasoning_text(block)
        return nil if text.blank?

        { type: "text", text: text }
      end

      def self.normalize_server_tool_use_for_replay(block)
        input = block[:input] || block["input"]
        return block unless input.is_a?(Hash)

        outputs = input[:outputs] || input["outputs"]
        return block unless outputs.is_a?(Hash)

        normalized_input = input.merge(outputs: outputs.values)
        normalized_input.delete(:outputs) if input.key?("outputs") && !input.key?(:outputs)
        normalized_input["outputs"] = outputs.values if input.key?("outputs")

        normalized = block.merge(input: normalized_input)
        normalized.delete(:input) if block.key?("input") && !block.key?(:input)
        normalized["input"] = normalized_input if block.key?("input")
        normalized
      end

      def self.convert_server_tool_use_to_tool_use(block)
        converted = block.merge(type: "tool_use")
        converted.delete(:type) if block.key?("type") && !block.key?(:type)
        converted["type"] = "tool_use" if block.key?("type")
        converted
      end

      def self.convert_server_tool_result_to_tool_result(block)
        converted = block.merge(type: "tool_result")
        converted.delete(:type) if block.key?("type") && !block.key?(:type)
        converted["type"] = "tool_result" if block.key?("type")

        content = converted[:content] || converted["content"]
        if content.is_a?(Hash)
          converted = converted.merge(content: JSON.generate(content))
          converted.delete(:content) if block.key?("content") && !block.key?(:content)
          converted["content"] = JSON.generate(content) if block.key?("content")
        end

        converted
      end

      def self.relocate_assistant_tool_results(messages)
        messages.flat_map do |message|
          next message unless message.is_a?(Hash)

          role = message[:role] || message["role"]
          content = message[:content] || message["content"]
          next message unless role == "assistant" && content.is_a?(Array)

          tool_results, assistant_content = content.partition do |block|
            block.is_a?(Hash) && (block[:type] || block["type"]) == "tool_result"
          end
          next message if tool_results.empty?

          relocated = []
          relocated << message.merge(content: assistant_content) unless assistant_content.empty?
          relocated << { role: "user", content: tool_results }
          relocated
        end
      end

      def self.extract_reasoning_text(block)
        return block[:thinking] if block[:thinking].is_a?(String)
        return block[:reasoning] if block[:reasoning].is_a?(String)

        summary = block[:summary]
        if summary.is_a?(Array)
          text = summary.filter_map do |item|
            next item if item.is_a?(String)
            next unless item.is_a?(Hash)

            item[:text] || item[:summary_text] || item[:reasoning]
          end.join("\n")
          return text if text.present?
        end

        nil
      end

      def self.same_model_replay?(message, target_provider:, target_api:, target_model:)
        provider = message[:provider] || message["provider"]
        api = message[:api] || message["api"]
        model = message[:model] || message["model"]

        provider == target_provider && api == target_api && model == target_model
      end

      def self.same_provider_api_replay?(message, target_provider:, target_api:)
        provider = message[:provider] || message["provider"]
        api = message[:api] || message["api"]

        provider == target_provider && api == target_api
      end

      def self.message_metadata_present?(message)
        provider = message[:provider] || message["provider"]
        api = message[:api] || message["api"]
        model = message[:model] || message["model"]

        provider.present? && api.present? && model.present?
      end

      private_class_method :sanitize_message, :sanitize_content_block, :normalize_server_tool_use_for_replay,
        :convert_server_tool_use_to_tool_use, :convert_server_tool_result_to_tool_result,
        :relocate_assistant_tool_results, :extract_reasoning_text, :same_model_replay?,
        :same_provider_api_replay?, :message_metadata_present?
    end
  end
end
