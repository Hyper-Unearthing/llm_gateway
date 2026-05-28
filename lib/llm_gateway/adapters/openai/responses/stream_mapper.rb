# frozen_string_literal: true

require "json"

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
            when "response.output_item.done"
              output_item_done_patches(data)
            when "response.content_part.added"
              content_part_added_patches(data)
            when "response.content_part.done", "response.output_text.done"
              content_part_done_patches(data)
            when "response.code_interpreter_call_code.delta"
              code_interpreter_code_delta_patches(data)
            when "response.code_interpreter_call.in_progress", "response.code_interpreter_call.interpreting", "response.code_interpreter_call.completed", "response.code_interpreter_call_code.done"
              []
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
                  role: "assistant",
                  timestamp: timestamp_milliseconds(response[:created_at])
                }.compact
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
                  delta: { role: item[:role] || "assistant" }
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
            when "code_interpreter_call"
              state = code_interpreter_state[data[:output_index] || 0] = {
                id: item[:id],
                container_id: item[:container_id],
                outputs: item[:outputs],
                input_opened: false,
                input_closed: false
              }
              container_id_to_tool_id[state[:container_id]] = state[:id] if state[:container_id]

              [
                {
                  type: :tool_start,
                  delta: "",
                  id: item[:id],
                  name: "code_interpreter_call",
                  tool_type: "server_tool_use"
                }
              ]
            else
              []
            end
          end

          def output_item_done_patches(data)
            item = data[:item] || {}

            case item[:type]
            when "code_interpreter_call"
              code_interpreter_done_patches(data[:output_index] || 0, item)
            when "message"
              container_file_citation_patches(item)
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

            citations = container_file_citation_patches(data)
            return citations unless accumulator.active_block_type == :text

            [ { type: :text_end, delta: "" } ] + citations
          end

          def code_interpreter_code_delta_patches(data)
            output_index = data[:output_index] || 0
            state = code_interpreter_state[output_index] ||= {
              id: nil,
              container_id: nil,
              outputs: nil,
              input_opened: false,
              input_closed: false
            }
            delta = escape_json_string_fragment(data[:delta] || "")
            delta = "{\"code\":\"#{delta}" unless state[:input_opened]
            state[:input_opened] = true

            [ { type: :tool_delta, delta: } ]
          end

          def code_interpreter_done_patches(output_index, item)
            state = code_interpreter_state[output_index] ||= {}
            state[:id] ||= item[:id]
            state[:container_id] = item[:container_id] if item.key?(:container_id)
            state[:outputs] = item[:outputs] if item.key?(:outputs)
            container_id_to_tool_id[state[:container_id]] = state[:id] if state[:container_id] && state[:id]
            return [] if state[:input_closed]

            opening = state[:input_opened] ? "" : "{\"code\":\""
            state[:input_opened] = true
            closing = "\"," + JSON.generate(container_id: state[:container_id], outputs: state[:outputs])[1..]
            state[:input_closed] = true

            [
              { type: :tool_delta, delta: opening + closing },
              { type: :tool_end, delta: "" }
            ]
          end

          def container_file_citation_patches(data)
            extract_annotations(data).filter_map do |annotation|
              next unless annotation[:type] == "container_file_citation"

              container_id = annotation[:container_id]
              file_id = annotation[:file_id]
              filename = annotation[:filename]
              tool_id = container_id_to_tool_id[container_id]
              next unless tool_id

              key = [ tool_id, container_id, file_id, filename ]
              next if emitted_citation_keys[key]

              emitted_citation_keys[key] = true
              {
                type: :tool_result_start,
                delta: JSON.generate(container_id:, file_id:, filename:),
                tool_use_id: tool_id,
                name: "container_file_citation_tool_result"
              }
            end.flat_map { |start| [ start, { type: :tool_result_end, delta: "" } ] }
          end

          def extract_annotations(data)
            annotations = []
            annotations.concat(Array(data[:annotations]))
            annotations.concat(Array(data.dig(:part, :annotations)))
            annotations.concat(Array(data.dig(:item, :annotations)))
            Array(data.dig(:item, :content)).each do |content_part|
              annotations.concat(Array(content_part[:annotations])) if content_part.is_a?(Hash)
            end
            annotations
          end

          def escape_json_string_fragment(value)
            JSON.generate(value)[1...-1]
          end

          def response_completed_patches(response)
            response ||= {}
            patch = {
              type: :message_delta,
              delta: {
                id: response[:id],
                model: response[:model],
                role: "assistant",
                timestamp: timestamp_milliseconds(response[:created_at]),
                stop_reason: stop_reason_for(response)
              }.compact
            }
            patch[:usage] = usage(response) if response.key?(:usage)

            [
              patch,
              { type: :message_end }
            ]
          end

          def usage(response)
            usage = response[:usage] || {}
            cache_read = token_count(usage.dig(:input_tokens_details, :cached_tokens))
            cache_write = token_count(
              usage.dig(:input_tokens_details, :cache_write_tokens),
              usage[:cache_write_tokens]
            )
            input_tokens = token_count(usage[:input_tokens])
            input = [ input_tokens - cache_read - cache_write, 0 ].max
            output = token_count(usage[:output_tokens])

            {
              input:,
              cache_write:,
              cache_read:,
              output:,
              total: input + cache_write + cache_read + output,
              raw: usage
            }
          end

          def token_count(*values)
            values.compact.first.to_i
          end

          def timestamp_milliseconds(unix_seconds)
            return nil if unix_seconds.nil?

            (unix_seconds.to_f * 1000).to_i
          end

          def stop_reason_for(response)
            output = response[:output] || []
            last_item = output.last || {}

            tool_seen? || last_item[:type] == "function_call" ? "tool_use" : "stop"
          end

          def tool_seen?
            accumulator.blocks.any? { |content_block| content_block && [ "tool_use", "server_tool_use" ].include?(content_block[:type]) }
          end

          def code_interpreter_state
            @code_interpreter_state ||= {}
          end

          def container_id_to_tool_id
            @container_id_to_tool_id ||= {}
          end

          def emitted_citation_keys
            @emitted_citation_keys ||= {}
          end
        end
      end
    end
  end
end
