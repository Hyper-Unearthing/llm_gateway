# frozen_string_literal: true

require_relative "../../stream_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      module Responses
        class StreamMapper < LlmGateway::Adapters::StreamMapper
          def map(chunk, &block)
            event_type = chunk[:event]
            data = chunk[:data] || {}
            raise_stream_error!(data) if event_type == "error" || data[:error] || data[:type] == "error"

            push_patches(patches_for(event_type, data), &block)
          end

          private

          def patches_for(event_type, data)
            case event_type
            when "response.created"
              response_created_patches(data[:response])
            when "response.output_item.added"
              output_item_added_patches(data)
            when "response.content_part.added"
              content_part_added_patches(data)
            when "response.content_part.done"
              content_part_done_patches(data)
            when "response.output_text.delta"
              [ { type: :text_delta, delta: data[:delta] || "" } ]
            when "response.function_call_arguments.delta"
              [ { type: :tool_delta, delta: data[:delta] || "" } ]
            when "response.function_call_arguments.done"
              [ { type: :tool_end, delta: "" } ]
            when "response.reasoning_summary_part.added"
              [ { type: :reasoning_start, delta: "", signature: "" } ]
            when "response.reasoning_summary_text.delta"
              [ { type: :reasoning_delta, delta: data[:delta] || "", signature: "" } ]
            when "response.reasoning_summary_part.done"
              [ { type: :reasoning_end, delta: "", signature: "" } ]
            when "response.completed"
              response_completed_patches(data[:response])
            else
              []
            end
          end

          def response_created_patches(response)
            response ||= {}

            [
              {
                type: :message_start,
                delta: {
                  id: response[:id],
                  model: response[:model],
                  role: "assistant"
                }.compact,
                usage_increment: {}
              }
            ]
          end

          def output_item_added_patches(data)
            item = data[:item] || {}

            case item[:type]
            when "message"
              return [] unless accumulator.message_hash.empty?

              [
                {
                  type: :message_start,
                  delta: { role: item[:role] || "assistant" },
                  usage_increment: {}
                }
              ]
            when "function_call"
              [
                {
                  type: :tool_start,
                  delta: "",
                  id: item[:call_id] || item[:id],
                  name: item[:name]
                }
              ]
            else
              []
            end
          end

          def content_part_added_patches(data)
            part = data[:part] || {}
            return [] unless part[:type] == "output_text"

            [ { type: :text_start, delta: "" } ]
          end

          def content_part_done_patches(data)
            part = data[:part] || {}
            return [] unless part.empty? || part[:type] == "output_text"

            [ { type: :text_end, delta: "" } ]
          end

          def response_completed_patches(response)
            response ||= {}

            [
              {
                type: accumulator.message_hash.empty? ? :message_start : :message_delta,
                delta: {
                  id: response[:id],
                  model: response[:model],
                  role: "assistant",
                  stop_reason: stop_reason_for(response)
                }.compact,
                usage_increment: usage_increment(response)
              }
            ]
          end

          def usage_increment(response)
            usage = response[:usage] || {}

            {
              input_tokens: usage[:input_tokens] || 0,
              cache_creation_input_tokens: 0,
              cache_read_input_tokens: usage.dig(:input_tokens_details, :cached_tokens) || 0,
              output_tokens: usage[:output_tokens] || 0,
              reasoning_tokens: usage.dig(:output_tokens_details, :reasoning_tokens) || 0
            }
          end

          def stop_reason_for(response)
            output = response[:output] || []
            last_item = output.last || {}

            tool_seen? || last_item[:type] == "function_call" ? "tool_use" : "stop"
          end

          def tool_seen?
            accumulator.blocks.any? { |content_block| content_block && content_block[:type] == "tool_use" }
          end
        end
      end
    end
  end
end
