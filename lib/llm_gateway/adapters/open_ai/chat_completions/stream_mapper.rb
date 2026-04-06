# frozen_string_literal: true

require_relative "../../structs"

module LlmGateway
  module Adapters
    module OpenAi
      module ChatCompletions
        class StreamMapper
          def map(chunk)
            queued_event = shift_queued_event
            return queued_event if queued_event

            data = chunk[:data] || {}
            raise_stream_error!(data) if chunk[:event] == "error" || data[:error] || data[:type] == "error"

            choices = data[:choices] || []

            if choices.empty?
              return message_event(
                delta: pending_finish_delta,
                usage_increment: usage_increment(data)
              )
            end

            choice = choices.first || {}
            delta = choice[:delta] || {}
            finish_reason = choice[:finish_reason]

            event = map_choice_delta(data, choice, delta)
            return event if event

            return finish_event_for(finish_reason) if finish_reason

            nil
          end

          private

          def map_choice_delta(data, choice, delta)
            if !message_started? && delta[:tool_calls]&.any?
              @message_started = true
              stash_message_attributes(data, delta)
              return tool_event(delta[:tool_calls].first)
            end

            if !message_started? && (delta.key?(:role) || data[:id] || data[:model])
              @message_started = true
              return AssistantStreamMessageEvent.new(
                type: :message_start,
                delta: {
                  id: data[:id],
                  model: data[:model],
                  role: delta[:role]
                }.compact,
                usage_increment: {}
              )
            end

            if (content = delta[:content]) && !content.empty?
              return text_event(content, choice[:index] || 0)
            end

            return tool_event(delta[:tool_calls].first) if delta[:tool_calls]&.any?

            nil
          end

          def finish_event_for(finish_reason)
            normalized = normalize_stop_reason(finish_reason)
            stash_pending_finish_delta(stop_reason: normalized)

            case normalized
            when "tool_use"
              AssistantStreamEvent.new(type: :tool_end, content_index: last_started_tool_index || 0, delta: "")
            else
              AssistantStreamEvent.new(type: :text_end, content_index: last_started_text_index || 0, delta: "")
            end
          end

          def message_event(delta:, usage_increment: {})
            AssistantStreamMessageEvent.new(
              type: pending_message_attributes.empty? ? :message_delta : :message_start,
              delta: pending_message_attributes.merge(delta),
              usage_increment:
            ).tap do
              clear_pending_message_attributes
              clear_pending_finish_delta
            end
          end

          def usage_increment(data)
            usage = data[:usage] || {}

            {
              input_tokens: usage[:prompt_tokens] || 0,
              cache_creation_input_tokens: 0,
              cache_read_input_tokens: usage.dig(:prompt_tokens_details, :cached_tokens) || 0,
              output_tokens: usage[:completion_tokens] || 0,
              reasoning_tokens: usage.dig(:completion_tokens_details, :reasoning_tokens) || 0
            }
          end

          def text_event(content, content_index)
            @last_started_text_index = content_index

            if started_text_blocks.include?(content_index)
              AssistantStreamEvent.new(type: :text_delta, content_index:, delta: content)
            else
              started_text_blocks << content_index
              AssistantStreamEvent.new(type: :text_start, content_index:, delta: content)
            end
          end

          def tool_event(tool_call)
            tool_index = tool_call[:index] || 0
            @last_started_tool_index = tool_index
            function = tool_call[:function] || {}
            arguments = function[:arguments] || ""

            unless started_tool_blocks.include?(tool_index)
              pending_tool_calls[tool_index] = merge_tool_call(pending_tool_calls[tool_index], tool_call)
              pending = pending_tool_calls[tool_index]

              return nil unless pending[:id] && pending.dig(:function, :name)

              started_tool_blocks << tool_index
              return AssistantToolStartEvent.new(
                type: :tool_start,
                content_index: tool_index,
                delta: "",
                id: pending[:id],
                name: pending.dig(:function, :name)
              )
            end

            AssistantStreamEvent.new(type: :tool_delta, content_index: tool_index, delta: arguments)
          end

          def stash_message_attributes(data, delta)
            @pending_message_attributes = {
              id: data[:id],
              model: data[:model],
              role: delta[:role]
            }.compact
          end

          def pending_message_attributes
            @pending_message_attributes ||= {}
          end

          def clear_pending_message_attributes
            @pending_message_attributes = {}
          end

          def stash_pending_finish_delta(delta)
            @pending_finish_delta = pending_finish_delta.merge(delta)
          end

          def pending_finish_delta
            @pending_finish_delta ||= {}
          end

          def clear_pending_finish_delta
            @pending_finish_delta = {}
          end

          def merge_tool_call(existing, incoming)
            existing ||= {}
            incoming ||= {}

            existing_function = existing[:function] || {}
            incoming_function = incoming[:function] || {}

            {
              index: incoming[:index] || existing[:index],
              id: incoming[:id] || existing[:id],
              type: incoming[:type] || existing[:type],
              function: {
                name: incoming_function[:name] || existing_function[:name],
                arguments: "#{existing_function[:arguments]}#{incoming_function[:arguments]}"
              }
            }
          end

          def normalize_stop_reason(finish_reason)
            case finish_reason
            when "tool_calls"
              "tool_use"
            else
              finish_reason
            end
          end

          def message_started?
            @message_started ||= false
          end

          def started_text_blocks
            @started_text_blocks ||= []
          end

          def started_tool_blocks
            @started_tool_blocks ||= []
          end

          def pending_tool_calls
            @pending_tool_calls ||= {}
          end

          def last_started_text_index
            @last_started_text_index
          end

          def last_started_tool_index
            @last_started_tool_index
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
