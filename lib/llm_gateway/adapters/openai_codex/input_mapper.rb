# frozen_string_literal: true

require "json"
require_relative "../open_ai/responses/input_mapper"

module LlmGateway
  module Adapters
    module OpenAiCodex
      # Custom input mapper for the Codex backend.
      #
      # The Codex Responses endpoint rejects several content block types that
      # the standard OpenAI Responses InputMapper passes through:
      #   - "reasoning" and "summary_text" blocks are never accepted as input.
      #   - "thinking" blocks are only valid when they carry an encrypted
      #     `signature`; unsigned thinking blocks must be dropped.
      #
      # Additional normalisation:
      #   - Tool-result output is coerced to recognised Responses input types
      #     (input_text / input_image).
      #   - Assistant text content is always sent as "output_text" (not
      #     "input_text") because Codex is strict about directionality.
      #   - function_call / tool_use blocks inside an assistant turn are
      #     promoted to top-level function_call items so that Codex can match
      #     them against the subsequent function_call_output items.
      class InputMapper < OpenAi::Responses::InputMapper
        def self.map_messages(messages)
          return messages unless messages.is_a?(Array)

          mapper  = message_mapper
          stripped = strip_reasoning_blocks(messages)

          mapped = stripped.each_with_object([]) do |msg, acc|
            next unless msg.is_a?(Hash)

            role    = msg[:role]
            content = msg[:content]

            if %w[user developer].include?(role) && tool_result_message?(content)
              # Responses API expects tool results as top-level input items.
              # Also normalise nested tool_result output blocks to Responses
              # input types (text → input_text, image → input_image).
              content.each { |part| acc << map_tool_result_for_responses(part, mapper) }
              next
            end

            if role == "assistant" && content.is_a?(Array)
              acc.concat(map_assistant_content(content, mapper))
              next
            end

            mapped_content =
              if content.is_a?(Array)
                content.map { |part| mapper.map_content(part) }
              else
                [ mapper.map_content(content) ]
              end

            acc << { role: role, content: mapped_content }
          end

          normalize_assistant_content_types(mapped)
        end

        # Recursively strip Codex-incompatible content blocks from a message tree.
        #
        #   "reasoning"    → always removed
        #   "summary_text" → always removed
        #   "thinking"     → removed unless :signature is present
        def self.strip_reasoning_blocks(obj)
          case obj
          when Array
            obj.map { |item| strip_reasoning_blocks(item) }.compact
          when Hash
            type = obj[:type]
            return nil if %w[reasoning summary_text].include?(type)
            return nil if type == "thinking" && obj[:signature].nil?

            obj.each_with_object({}) do |(k, v), acc|
              result = strip_reasoning_blocks(v)
              acc[k] = result unless result.nil?
            end
          else
            obj
          end
        end

        # Ensure assistant messages carry "output_text" rather than "input_text".
        # The BidirectionalMessageMapper maps plain text blocks to "input_text";
        # Codex is strict about directionality and rejects "input_text" on the
        # assistant side.
        def self.normalize_assistant_content_types(messages)
          return messages unless messages.is_a?(Array)

          messages.map do |msg|
            next msg unless msg.is_a?(Hash) && msg[:role] == "assistant" && msg[:content].is_a?(Array)

            msg.merge(
              content: msg[:content].map do |part|
                part.is_a?(Hash) && part[:type] == "input_text" ? part.merge(type: "output_text") : part
              end
            )
          end
        end

        def self.tool_result_message?(content)
          content.is_a?(Array) &&
            content.first.is_a?(Hash) &&
            content.first[:type] == "tool_result"
        end

        # Map assistant content blocks into Codex-compatible top-level items.
        #
        # - thinking with signature  → parsed JSON reasoning item (the encrypted
        #                               signature *is* the serialised item)
        # - tool_use / function_call → top-level function_call item
        # - text / *_text variants   → output_text inside an assistant content block
        # - anything else            → delegated to the BidirectionalMessageMapper
        def self.map_assistant_content(content, mapper)
          text_parts = []
          items      = []

          content.each do |part|
            next unless part.is_a?(Hash)

            case part[:type]
            when "tool_use", "function_call"
              call_id   = part[:id] || part[:call_id]
              arguments = part[:input] || part[:arguments] || {}
              arguments = JSON.generate(arguments) unless arguments.is_a?(String)

              items << {
                type: "function_call",
                call_id: call_id,
                name: part[:name],
                arguments: arguments
              }.compact

            when "thinking"
              # Only signed thinking blocks survive strip_reasoning_blocks;
              # the signature payload is the full reasoning item JSON.
              signature = part[:signature]
              if signature
                begin
                  items << JSON.parse(signature, symbolize_names: true)
                rescue JSON::ParserError
                  # Malformed signature — silently drop.
                end
              end

            when "text", "input_text", "output_text"
              text_parts << { type: "output_text", text: part[:text].to_s }

            else
              mapped = mapper.map_content(part)
              text_parts << mapped if mapped
            end
          end

          # Text parts form a single assistant message; tool/reasoning items follow.
          items.unshift({ role: "assistant", content: text_parts }) if text_parts.any?
          items
        end

        # Wrap a tool_result part in the Responses wire format, normalising the
        # nested output content types along the way.
        def self.map_tool_result_for_responses(part, mapper)
          return mapper.map_content(part) unless part.is_a?(Hash) && part[:type] == "tool_result"

          mapper.map_content(part.merge(content: normalize_tool_result_output(part[:content])))
        end

        # Coerce each element of a tool result's output array to a Responses
        # input type (input_text or input_image).
        def self.normalize_tool_result_output(output)
          Array(output).map do |item|
            case item
            when String
              { type: "input_text", text: item }
            when Hash
              type = item[:type] || item["type"]
              case type
              when "text", "input_text", "output_text"
                { type: "input_text", text: (item[:text] || item["text"]).to_s }
              when "image", "input_image"
                data      = item[:data]      || item["data"]
                mime      = item[:mimeType]  || item["mimeType"] ||
                            item[:media_type] || item["media_type"] || "image/png"
                image_url = item[:image_url] || item["image_url"] ||
                            "data:#{mime};base64,#{data}"
                { type: "input_image", image_url: image_url }
              else
                item
              end
            else
              { type: "input_text", text: item.to_s }
            end
          end
        end

        private_class_method :strip_reasoning_blocks, :normalize_assistant_content_types,
                             :tool_result_message?, :map_assistant_content,
                             :map_tool_result_for_responses, :normalize_tool_result_output
      end
    end
  end
end
