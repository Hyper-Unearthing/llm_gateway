# frozen_string_literal: true

require_relative "../../structs"

module LlmGateway
  module Adapters
    module OpenAi
      module Responses
        class StreamMapper
          def map(chunk)
            queued_event = shift_queued_event
            return queued_event if queued_event

            event_type = chunk[:event]
            data = chunk[:data] || {}
            raise_stream_error!(data) if event_type == "error" || data[:error] || data[:type] == "error"

            case event_type
            when "response.created"
              stash_response(data[:response])
              nil
            when "response.output_item.added"
              map_output_item_added(data)
            when "response.output_item.done"
              map_output_item_done(data)
            when "response.content_part.added"
              map_content_part_added(data)
            when "response.content_part.done", "response.output_text.done"
              map_text_done(data)
            when "response.output_text.delta"
              AssistantStreamEvent.new(
                type: :text_delta,
                content_index: content_index_for(data[:output_index] || 0),
                delta: data[:delta] || ""
              )
            when "response.function_call_arguments.delta"
              AssistantStreamEvent.new(
                type: :tool_delta,
                content_index: content_index_for(data[:output_index] || 0),
                delta: data[:delta] || ""
              )
            when "response.function_call_arguments.done"
              map_tool_done(data)
            when "response.reasoning_summary_text.delta"
              output_index = data[:output_index] || 0
              mark_reasoning_has_content(output_index)
              AssistantStreamReasoningEvent.new(
                type: :reasoning_delta,
                content_index: content_index_for(output_index),
                delta: data[:delta] || "",
                signature: ""
              )
            when "response.completed"
              map_response_completed(data[:response])
            else
              nil
            end
          end

          private

          def map_output_item_added(data)
            item = data[:item] || {}
            output_index = data[:output_index] || 0

            case item[:type]
            when "reasoning"
              mark_reasoning_started(output_index)
              AssistantStreamReasoningEvent.new(
                type: :reasoning_start,
                content_index: register_content_index(output_index),
                delta: "",
                signature: ""
              )
            when "message"
              register_content_index(output_index)
              ensure_message_started(role: item[:role] || "assistant")
            when "function_call"
              stash_role("assistant")
              mark_tool_started(output_index)
              AssistantToolStartEvent.new(
                type: :tool_start,
                content_index: register_content_index(output_index),
                delta: "",
                id: item[:call_id] || item[:id],
                name: item[:name]
              )
            else
              nil
            end
          end

          def map_output_item_done(data)
            item = data[:item] || {}
            output_index = data[:output_index] || 0

            case item[:type]
            when "reasoning"
              map_reasoning_done(output_index, item)
            when "function_call"
              map_function_call_done(output_index, item)
            else
              nil
            end
          end

          def map_reasoning_done(output_index, item)
            content_index = content_index_for(output_index)
            summary_text = extract_reasoning_summary_text(item)

            if reasoning_started_without_content?(output_index) && !summary_text.empty?
              queue_event(
                AssistantStreamReasoningEvent.new(
                  type: :reasoning_end,
                  content_index:,
                  delta: "",
                  signature: ""
                )
              )
              mark_reasoning_completed(output_index)
              return AssistantStreamReasoningEvent.new(
                type: :reasoning_delta,
                content_index:,
                delta: summary_text,
                signature: ""
              )
            end

            mark_reasoning_completed(output_index)
            AssistantStreamReasoningEvent.new(
              type: :reasoning_end,
              content_index:,
              delta: "",
              signature: ""
            )
          end

          def map_function_call_done(output_index, item)
            return nil if tool_started?(output_index)

            mark_tool_started(output_index)
            queue_event(
              AssistantStreamEvent.new(
                type: :tool_end,
                content_index: content_index_for(output_index),
                delta: ""
              )
            )

            AssistantToolStartEvent.new(
              type: :tool_start,
              content_index: register_content_index(output_index),
              delta: "",
              id: item[:call_id] || item[:id],
              name: item[:name]
            )
          end

          def map_content_part_added(data)
            part = data[:part] || {}
            return nil unless part[:type] == "output_text"

            AssistantStreamEvent.new(
              type: :text_start,
              content_index: content_index_for(data[:output_index] || 0),
              delta: ""
            )
          end

          def map_text_done(data)
            AssistantStreamEvent.new(
              type: :text_end,
              content_index: content_index_for(data[:output_index] || 0),
              delta: ""
            )
          end

          def map_tool_done(data)
            AssistantStreamEvent.new(
              type: :tool_end,
              content_index: content_index_for(data[:output_index] || 0),
              delta: ""
            )
          end

          def map_response_completed(response)
            stash_response(response)
            AssistantStreamMessageEvent.new(
              type: message_started? ? :message_delta : :message_start,
              delta: pending_message_attributes.merge(role: pending_message_attributes[:role] || "assistant", stop_reason: stop_reason_for(response)),
              usage_increment: usage_increment(response)
            ).tap do
              @message_started = true
              clear_pending_message_attributes
            end
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

            tool_state.any? || last_item[:type] == "function_call" ? "tool_use" : "stop"
          end

          def ensure_message_started(role: "assistant")
            return nil if message_started?

            @message_started = true
            AssistantStreamMessageEvent.new(
              type: :message_start,
              delta: pending_message_attributes.merge(role: role).compact,
              usage_increment: {}
            ).tap do
              clear_pending_message_attributes
            end
          end

          def extract_reasoning_summary_text(item)
            Array(item[:summary]).filter_map do |summary|
              next summary[:text] if summary.is_a?(Hash) && summary[:text]
              next summary[:summary] if summary.is_a?(Hash) && summary[:summary]
              next summary if summary.is_a?(String)
            end.join
          end

          def mark_reasoning_started(output_index)
            reasoning_state[output_index] = :started
          end

          def mark_reasoning_has_content(output_index)
            reasoning_state[output_index] = :has_content
          end

          def mark_reasoning_completed(output_index)
            reasoning_state[output_index] = :completed
          end

          def reasoning_started_without_content?(output_index)
            reasoning_state[output_index] == :started
          end

          def reasoning_state
            @reasoning_state ||= {}
          end

          def mark_tool_started(output_index)
            tool_state[output_index] = :started
          end

          def tool_started?(output_index)
            tool_state[output_index] == :started
          end

          def tool_state
            @tool_state ||= {}
          end

          def stash_response(response)
            response ||= {}
            @pending_message_attributes = pending_message_attributes.merge(
              id: response[:id],
              model: response[:model]
            ).compact
          end

          def stash_role(role)
            @pending_message_attributes = pending_message_attributes.merge(role:)
          end

          def pending_message_attributes
            @pending_message_attributes ||= {}
          end

          def clear_pending_message_attributes
            @pending_message_attributes = {}
          end

          def register_content_index(output_index)
            content_index_map[output_index] ||= next_content_index!
          end

          def content_index_for(output_index)
            content_index_map.fetch(output_index) { register_content_index(output_index) }
          end

          def next_content_index!
            @next_content_index ||= 0
            current = @next_content_index
            @next_content_index += 1
            current
          end

          def content_index_map
            @content_index_map ||= {}
          end

          def message_started?
            @message_started ||= false
          end

          def queue_event(event)
            queued_events << event
          end

          def shift_queued_event
            queued_events.shift
          end

          def queued_events
            @queued_events ||= []
          end

          def raise_stream_error!(data)
            error = data[:error].is_a?(Hash) ? data[:error] : data
            message = error[:message] || "Stream error"
            code = error[:code] || error[:type]

            if LlmGateway::Errors.context_overflow_message?(message)
              raise LlmGateway::Errors::PromptTooLong.new(message, code)
            end

            raise LlmGateway::Errors::APIStatusError.new(message, code)
          end
        end
      end
    end
  end
end
