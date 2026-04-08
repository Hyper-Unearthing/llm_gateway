# frozen_string_literal: true

module LlmGateway
  module Adapters
    class InputMessageSanitizer
      def self.sanitize(messages, target_provider:, target_api:, target_model:)
        return messages unless messages.is_a?(Array)

        messages.map do |message|
          sanitize_message(
            message,
            target_provider: target_provider,
            target_api: target_api,
            target_model: target_model
          )
        end
      end

      def self.sanitize_message(message, target_provider:, target_api:, target_model:)
        return message unless message.is_a?(Hash)

        role = message[:role] || message["role"]
        content = message[:content] || message["content"]
        return message unless role == "assistant" && content.is_a?(Array)
        return message unless message_metadata_present?(message)

        same_model_replay = same_model_replay?(message, target_provider:, target_api:, target_model:)

        sanitized_content = content.each_with_object([]) do |block, acc|
          sanitized = sanitize_content_block(block, same_model_replay: same_model_replay)
          next if sanitized.nil?

          if sanitized.is_a?(Array)
            acc.concat(sanitized)
          else
            acc << sanitized
          end
        end

        message.merge(content: sanitized_content)
      end

      def self.sanitize_content_block(block, same_model_replay:)
        return block unless block.is_a?(Hash)

        type = block[:type] || block["type"]
        return block unless %w[thinking reasoning].include?(type)
        return block if same_model_replay

        text = extract_reasoning_text(block)
        return nil if text.nil? || text.strip.empty?

        { type: "text", text: text }
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
          return text unless text.empty?
        end

        nil
      end

      def self.same_model_replay?(message, target_provider:, target_api:, target_model:)
        provider = message[:provider] || message["provider"]
        api = message[:api] || message["api"]
        model = message[:model] || message["model"]

        provider == target_provider && api == target_api && model == target_model
      end

      def self.message_metadata_present?(message)
        provider = message[:provider] || message["provider"]
        api = message[:api] || message["api"]
        model = message[:model] || message["model"]

        !provider.nil? && !api.nil? && !model.nil?
      end

      private_class_method :sanitize_message, :sanitize_content_block, :extract_reasoning_text, :same_model_replay?, :message_metadata_present?
    end
  end
end
