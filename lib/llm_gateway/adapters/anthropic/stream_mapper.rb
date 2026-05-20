# frozen_string_literal: true

require_relative "../stream_mapper"

module LlmGateway
  module Adapters
    module Anthropic
      class StreamMapper < LlmGateway::Adapters::StreamMapper
        def map(chunk, &block)
          case chunk[:event]
          when "message_start"
            delta = {
              id: chunk.dig(:data, :message, :id),
              model: chunk.dig(:data, :message, :model),
              role: chunk.dig(:data, :message, :role)
            }
            usage_increment = chunk.dig(:data, :message, :usage) || {}

            accumulator.push({ type: :message_start, usage_increment:, delta: }, &block)
          when "content_block_start"
            content_block = chunk.dig(:data, :content_block) || {}
            @current_content_block_type = content_block[:type]

            case @current_content_block_type
            when "thinking"
              accumulator.push({ type: :reasoning_start, delta: content_block[:thinking], signature: "" }, &block)
            when "text"
              accumulator.push({ type: :text_start, delta: content_block[:text] }, &block)
            when "tool_use"
              accumulator.push(
                {
                  type: :tool_start,
                  delta: "",
                  id: content_block[:id],
                  name: content_block[:name]
                },
                &block
              )
            end
          when "content_block_delta"
            case @current_content_block_type
            when "thinking"
              delta = chunk.dig(:data, :delta, :thinking)
              signature = chunk.dig(:data, :delta, :signature) || ""
              accumulator.push({ type: :reasoning_delta, signature:, delta: }, &block)
            when "text"
              delta = chunk.dig(:data, :delta, :text)
              accumulator.push({ type: :text_delta, delta: }, &block)
            when "tool_use"
              delta = chunk.dig(:data, :delta, :partial_json)
              accumulator.push({ type: :tool_delta, delta: }, &block)
            end
          when "content_block_stop"
            case @current_content_block_type
            when "thinking"
              accumulator.push({ type: :reasoning_end, delta: "", signature: "" }, &block)
            when "text"
              accumulator.push({ type: :text_end, delta: "" }, &block)
            when "tool_use"
              accumulator.push({ type: :tool_end, delta: "" }, &block)
            end
            @current_content_block_type = nil
          when "message_delta"
            delta = normalize_message_delta(chunk.dig(:data, :delta) || {})
            usage_increment = chunk.dig(:data, :usage) || {}

            accumulator.push({ type: :message_delta, usage_increment:, delta: }, &block)
          when "message_stop"
            accumulator.push({ type: :message_end }, &block)
          when "ping"
            nil
          when "error"
            raise_stream_error!(chunk.dig(:data, :error) || {}, overload_codes: [ "overloaded_error" ])
          end
        end

        private

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
