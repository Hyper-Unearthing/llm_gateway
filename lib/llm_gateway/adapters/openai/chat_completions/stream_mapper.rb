# frozen_string_literal: true

require_relative "../../stream_mapper"

module LlmGateway
  module Adapters
    module OpenAI
      module ChatCompletions
        class StreamMapper < LlmGateway::Adapters::StreamMapper
          def map(chunk, &block)
            data = chunk[:data] || {}
            raise_stream_error!(data) if chunk[:event] == "error" || data[:error] || data[:type] == "error"

            push_patches(patches_for(data), &block)
          end

          private

          def patches_for(data)
            choices = data[:choices] || []
            return final_usage_patches(data) if choices.empty?

            choice = choices.first || {}
            delta = choice[:delta] || {}
            patches = []
            active_block_type = accumulator.active_block_type
            active_tool = active_tool_block

            append_patches(patches, message_start_patches(data, delta))

            active_block_type, active_tool = append_patches(
              patches,
              reasoning_patches(delta[:reasoning], active_block_type:),
              active_block_type,
              active_tool
            )
            active_block_type, active_tool = append_patches(
              patches,
              text_patches(delta[:content], active_block_type:),
              active_block_type,
              active_tool
            )
            delta.fetch(:tool_calls, []).each do |tool_call|
              active_block_type, active_tool = append_patches(
                patches,
                patches_for_tool_call(tool_call, active_block_type:, active_tool:),
                active_block_type,
                active_tool
              )
            end
            append_patches(patches, finish_patches(choice[:finish_reason], active_block_type:))

            patches
          end

          def append_patches(patches, new_patches, active_block_type = nil, active_tool = nil)
            patches.concat(new_patches)

            new_patches.each do |patch|
              case patch[:type]
              when :text_start
                active_block_type = :text
                active_tool = nil
              when :reasoning_start
                active_block_type = :reasoning
                active_tool = nil
              when :tool_start
                active_block_type = :tool
                active_tool = { id: patch[:id], name: patch[:name] }
              when :text_end, :reasoning_end, :tool_end
                active_block_type = nil
                active_tool = nil
              end
            end

            [ active_block_type, active_tool ]
          end

          def message_start_patches(data, delta)
            return [] unless accumulator.message_hash.empty?

            return [] unless delta.key?(:role) ||
                             data[:id] ||
                             data[:model] ||
                             delta[:content] ||
                             delta[:reasoning] ||
                             delta[:tool_calls]&.any?

            [
              {
                type: :message_start,
                delta: {
                  id: data[:id],
                  model: data[:model],
                  role: delta[:role] || "assistant",
                  timestamp: timestamp_milliseconds(data[:created])
                }.compact,
                usage_increment: {}
              }
            ]
          end

          # Groq exposes OpenAI-compatible chat completion chunks, but may include
          # `delta.reasoning` before normal `delta.content`.
          def reasoning_patches(reasoning, active_block_type: accumulator.active_block_type)
            return [] if reasoning.to_s.empty?

            [
              *close_active_non_reasoning_patches(active_block_type:),
              {
                type: active_block_type == :reasoning ? :reasoning_delta : :reasoning_start,
                delta: reasoning,
                signature: ""
              }
            ]
          end

          def text_patches(content, active_block_type: accumulator.active_block_type)
            return [] if content.to_s.empty?

            [
              *close_active_non_text_patches(active_block_type:),
              {
                type: active_block_type == :text ? :text_delta : :text_start,
                delta: content
              }
            ]
          end

          def patches_for_tool_call(tool_call, active_block_type: accumulator.active_block_type, active_tool: active_tool_block)
            id = tool_call[:id]
            name = tool_call.dig(:function, :name)
            arguments = tool_call.dig(:function, :arguments).to_s

            patches = []

            if id || name
              if active_block_type == :tool
                patches.concat(close_active_block_patches(active_block_type:)) if new_active_tool?(id, name, active_tool:)
              else
                patches.concat(close_active_non_tool_patches(active_block_type:))
              end

              unless active_block_type == :tool && patches.empty?
                patches << {
                  type: :tool_start,
                  delta: "",
                  id: id,
                  name: name
                }
              end
            end

            patches << { type: :tool_delta, delta: arguments } unless arguments.empty?
            patches
          end

          def new_active_tool?(id, name, active_tool: active_tool_block)
            return true unless active_tool

            (id && active_tool[:id] != id) || (name && active_tool[:name] != name)
          end

          def active_tool_block
            return nil unless accumulator.active_tool?

            accumulator.blocks.reverse.find { |block| block&.fetch(:type, nil) == "tool_use" }
          end

          def close_active_block_patches(active_block_type: accumulator.active_block_type)
            case active_block_type
            when :text
              [ { type: :text_end, delta: "" } ]
            when :reasoning
              [ { type: :reasoning_end, delta: "", signature: "" } ]
            when :tool
              [ { type: :tool_end, delta: "" } ]
            else
              []
            end
          end

          def close_active_non_text_patches(active_block_type: accumulator.active_block_type)
            active_block_type == :text ? [] : close_active_block_patches(active_block_type:)
          end

          def close_active_non_reasoning_patches(active_block_type: accumulator.active_block_type)
            active_block_type == :reasoning ? [] : close_active_block_patches(active_block_type:)
          end

          def close_active_non_tool_patches(active_block_type: accumulator.active_block_type)
            active_block_type == :tool ? [] : close_active_block_patches(active_block_type:)
          end

          def finish_patches(finish_reason, active_block_type: accumulator.active_block_type)
            return [] unless finish_reason

            [
              *close_active_block_patches(active_block_type:),
              {
                type: :message_delta,
                delta: { stop_reason: normalize_stop_reason(finish_reason) },
                usage_increment: {}
              }
            ]
          end

          def final_usage_patches(data)
            [
              {
                type: accumulator.message_hash.empty? ? :message_start : :message_delta,
                delta: {},
                usage_increment: usage_increment(data)
              },
              { type: :message_end }
            ]
          end

          def usage_increment(data)
            usage = data[:usage] || {}
            cache_read = token_count(
              usage.dig(:prompt_tokens_details, :cached_tokens),
              usage[:prompt_cache_hit_tokens]
            )
            cache_write = token_count(
              usage.dig(:prompt_tokens_details, :cache_write_tokens),
              usage[:cache_write_tokens]
            )
            prompt_tokens = token_count(usage[:prompt_tokens])

            {
              input: [ prompt_tokens - cache_read - cache_write, 0 ].max,
              cache_write:,
              cache_read:,
              output: token_count(usage[:completion_tokens])
            }
          end

          def token_count(*values)
            values.compact.first.to_i
          end

          def timestamp_milliseconds(unix_seconds)
            return nil if unix_seconds.nil?

            (unix_seconds.to_f * 1000).to_i
          end

          def normalize_stop_reason(finish_reason)
            case finish_reason
            when "tool_calls"
              "tool_use"
            else
              finish_reason
            end
          end
        end
      end
    end
  end
end
