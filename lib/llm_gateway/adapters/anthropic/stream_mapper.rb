# frozen_string_literal: true

require "json"
require_relative "../structs.rb"

module LlmGateway
  module Adapters
    module Anthropic
      class StreamMapper
        def map(chunk)
          case chunk[:event]
          when "message_start"
            delta = {
              id: chunk.dig(:data, :message, :id),
              model: chunk.dig(:data, :message, :model),
              role: chunk.dig(:data, :message, :role)
            }
            usage_increment = chunk.dig(:data, :message, :usage) || {}

            AssistantStreamMessageEvent.new(type: :message_start, usage_increment:, delta:)
          when "content_block_start"
            content_index = chunk.dig(:data, :index)
            delta = chunk.dig(:data, :content_block, :text)
            current_type = chunk.dig(:data, :content_block, :type)
            normalized_type = normalize_content_block_type(current_type)
            content_block_types[content_index] = normalized_type

            case normalized_type
            when "thinking"
              AssistantStreamEvent.new(type: :reasoning_start, content_index:, delta:)
            when "text"
              AssistantStreamEvent.new(type: :text_start, content_index:, delta:)
            when "tool_use", "server_tool_use"
              id = chunk.dig(:data, :content_block, :id)
              name = chunk.dig(:data, :content_block, :name)
              AssistantToolStartEvent.new(type: :tool_start, content_index:, delta:, id:, name:, tool_type: current_type)
            when "server_tool_result"
              tool_use_id = chunk.dig(:data, :content_block, :tool_use_id)
              name = current_type
              content = chunk.dig(:data, :content_block, :content)
              result_delta = content.nil? ? "" : JSON.generate(content)
              AssistantToolResultStartEvent.new(type: :tool_result_start, content_index:, delta: result_delta, tool_use_id:, name:)
            end
          when "content_block_delta"
            content_index = chunk.dig(:data, :index)

            case content_block_types[content_index]
            when "thinking"
              delta = chunk.dig(:data, :delta, :thinking)
              signature = chunk.dig(:data, :delta, :signature)
              AssistantStreamReasoningEvent.new(type: :reasoning_delta, signature:, delta:, content_index:)
            when "text"
              delta = chunk.dig(:data, :delta, :text)
              AssistantStreamEvent.new(type: :text_delta, content_index:, delta:)
            when "tool_use", "server_tool_use"
              delta = chunk.dig(:data, :delta, :partial_json)
              AssistantStreamEvent.new(type: :tool_delta, content_index:, delta:)
            when "server_tool_result"
              content = chunk.dig(:data, :delta, :content)
              result_delta = content.nil? ? "" : JSON.generate(content)
              AssistantStreamEvent.new(type: :tool_result_delta, content_index:, delta: result_delta)
            end
          when "content_block_stop"
            content_index = chunk.dig(:data, :index)

            type = case content_block_types[content_index]
            when "thinking"
              :reasoning_end
            when "text"
              :text_end
            when "tool_use", "server_tool_use"
              :tool_end
            when "server_tool_result"
              :tool_result_end
            end
            # continue
            AssistantStreamEvent.new(type: type, content_index:, delta: "") if type != nil
          when "message_delta"
            delta = normalize_message_delta(chunk.dig(:data, :delta) || {})
            usage_increment = chunk.dig(:data, :usage) || {}

            AssistantStreamMessageEvent.new(type: :message_delta, usage_increment:, delta:)
          when "message_stop"
            AssistantStreamMessageEvent.new(type: :message_end, usage_increment: {}, delta: {})
          when "ping"
            nil
          when "error"
            error = chunk.dig(:data, :error) || {}
            message = error[:message] || "Stream error"
            code = error[:type]

            if LlmGateway::Errors.context_overflow_message?(message)
              raise LlmGateway::Errors::PromptTooLong.new(message, code)
            end

            if code == "overloaded_error"
              raise LlmGateway::Errors::OverloadError.new(message, code)
            end

            raise LlmGateway::Errors::APIStatusError.new(message, code)
          end
        end

        private

        def content_block_types
          @content_block_types ||= {}
        end

        def normalize_content_block_type(type)
          return type unless type&.end_with?("_tool_result")

          "server_tool_result"
        end

        def normalize_message_delta(delta)
          return delta unless delta[:stop_reason] || delta["stop_reason"]

          stop_reason = delta[:stop_reason] || delta["stop_reason"]
          normalized_stop_reason = case stop_reason
          when "end_turn"
            "stop"
          else
            stop_reason
          end

          delta.merge(stop_reason: normalized_stop_reason)
        end
      end
    end
  end
end
