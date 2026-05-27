# frozen_string_literal: true

require "json"

require_relative "../utils"
require_relative "structs"

module LlmGateway
  module Adapters
    class NormalizedStreamAccumulator
      # Contract:
      #
      # `push` accepts a single provider-independent, normalized stream event
      # patch hash. Event patches are never arrays; mappers call `push` once per
      # patch.
      #
      # Provider wire events such as Anthropic `message_start` /
      # `content_block_start`, OpenAI `response.output_text.delta`, etc. must be
      # translated by the mapper before calling this accumulator. The normalized
      # symbol `:message_start` below is allowed; the raw provider event string is
      # not.
      #
      # Accepted event shapes:
      #
      #   { type: :message_start, delta: { id: "...", model: "...", role: "assistant", timestamp: 1716650000000 } }
      #   { type: :message_delta, delta: { stop_reason: "stop" }, usage: { output: 2 } }
      #   { type: :message_end }
      #
      #   { type: :text_start, delta: "hi" }
      #   { type: :text_delta, delta: " there" }
      #   { type: :text_end, delta: "" }
      #
      #   { type: :reasoning_start, delta: "thinking", signature: "" }
      #   { type: :reasoning_delta, delta: "...", signature: "" }
      #   { type: :reasoning_end, delta: "", signature: "" }
      #
      #   { type: :tool_start, id: "...", name: "tool_name", delta: "" }
      #   { type: :tool_delta, delta: "{\"a\":" }
      #   { type: :tool_end, delta: "" }
      #
      # Mappers do not provide `content_index`. The accumulator assigns the next
      # public content index when a block starts and reuses the active content
      # index for that block's deltas and end event.
      #
      # Without source indexes, the accumulator cannot detect two interleaved
      # blocks of the same type. Providers that can interleave same-type blocks
      # must buffer or serialize them in the mapper before pushing normalized
      # events.
      #
      # The accumulator creates the public Assistant* event structs, updates its
      # accumulated message state, then yields the created event to the callback.
      attr_accessor :blocks, :message_hash, :usage_hash
      attr_reader :active_block_type, :final_message

      DEFAULT_USAGE = {
        input: 0,
        cache_write: 0,
        cache_read: 0,
        output: 0,
        total: 0
      }.freeze

      BLOCK_EVENT_TRANSITIONS = {
        text_start: { block_type: :text, phase: :start },
        text_delta: { block_type: :text, phase: :delta },
        text_end: { block_type: :text, phase: :end },
        tool_start: { block_type: :tool, phase: :start },
        tool_delta: { block_type: :tool, phase: :delta },
        tool_end: { block_type: :tool, phase: :end },
        reasoning_start: { block_type: :reasoning, phase: :start },
        reasoning_delta: { block_type: :reasoning, phase: :delta },
        reasoning_end: { block_type: :reasoning, phase: :end }
      }.freeze

      def initialize(provider: nil, api: nil)
        @provider = provider
        @api = api
        @message_hash = {}
        @usage_hash = DEFAULT_USAGE.dup
        @blocks = []
        @next_content_index = 0
        @active_block_type = nil
        @active_content_index = nil
        @timestamp = nil
      end

      def result
        ensure_timestamp!

        message_hash.merge(
          timestamp: @timestamp,
          usage: usage_hash,
          content: serialized_blocks
        )
      end

      def final_result
        result.merge(provider: @provider, api: @api)
      end

      def active_tool?
        active_block_type == :tool
      end

      def push(event_patch, &block)
        raise ArgumentError, "Normalized stream event patch must be a Hash" unless event_patch.is_a?(Hash)

        event_patch = symbolize_keys(event_patch)
        type = event_patch.fetch(:type).to_sym
        event_patch = prepare_event_patch(event_patch.merge(type:), type)
        ensure_timestamp!

        if type == :message_end
          @final_message = AssistantMessage.new(final_result)
          block.call(AssistantStreamMessageEndEvent.new(type:, message: final_message)) if block
          return nil
        end

        event = build_event(event_patch, partial: empty_partial)
        accumulate(event)
        content_index = event.content_index if event.respond_to?(:content_index)
        commit_block_transition(type, content_index)
        event = build_event(event_patch, partial: partial_message)
        block.call(event) if block

        nil
      end

      private

      def prepare_event_patch(event_patch, type)
        transition = BLOCK_EVENT_TRANSITIONS[type]
        return event_patch unless transition

        block_type = transition[:block_type]

        case transition[:phase]
        when :start
          validate_start!(block_type)
          event_patch.merge(content_index: @next_content_index)
        when :delta
          validate_delta!(type, block_type)
          event_patch.merge(content_index: @active_content_index)
        when :end
          validate_end!(block_type)
          event_patch.merge(content_index: @active_content_index)
        end
      end

      def validate_start!(block_type)
        return unless @active_block_type

        raise ArgumentError, "Cannot start #{block_type} block while #{@active_block_type} block is active"
      end

      def validate_delta!(type, block_type)
        unless @active_block_type
          raise ArgumentError, "Cannot apply #{type} without an active #{block_type} block"
        end
        return if @active_block_type == block_type

        raise ArgumentError, "Cannot apply #{type} while #{@active_block_type} block is active"
      end

      def validate_end!(block_type)
        unless @active_block_type
          raise ArgumentError, "Cannot end #{block_type} block without an active #{block_type} block"
        end
        return if @active_block_type == block_type

        raise ArgumentError, "Cannot end #{block_type} block while #{@active_block_type} block is active"
      end

      def commit_block_transition(type, content_index)
        transition = BLOCK_EVENT_TRANSITIONS[type]
        return unless transition

        case transition[:phase]
        when :start
          @active_block_type = transition[:block_type]
          @active_content_index = content_index
          @next_content_index += 1
        when :end
          @active_block_type = nil
          @active_content_index = nil
        end
      end

      def build_event(event_patch, partial:)
        event_patch = symbolize_keys(event_patch)
        type = event_patch.fetch(:type).to_sym

        case type
        when :message_start, :message_delta
          delta = symbolize_keys(event_patch[:delta] || {})
          raw_usage = event_patch[:usage] || delta.delete(:usage) || {}
          usage = raw_usage.empty? ? {} : normalized_usage(raw_usage)

          AssistantStreamMessageEvent.new(
            type:,
            delta:,
            usage:,
            partial:
          )
        when :tool_start
          AssistantToolStartEvent.new(
            type:,
            content_index: event_patch.fetch(:content_index),
            delta: string_value(event_patch[:delta]),
            id: event_patch[:id],
            name: event_patch[:name],
            partial:
          )
        when :reasoning_start, :reasoning_delta, :reasoning_end
          AssistantStreamReasoningEvent.new(
            type:,
            content_index: event_patch.fetch(:content_index),
            delta: string_value(event_patch[:delta]),
            signature: string_value(event_patch[:signature]),
            partial:
          )
        when :text_start, :text_delta, :text_end, :tool_delta, :tool_end
          AssistantStreamEvent.new(
            type:,
            content_index: event_patch.fetch(:content_index),
            delta: string_value(event_patch[:delta]),
            partial:
          )
        else
          raise ArgumentError, "Unsupported normalized stream event type: #{type.inspect}"
        end
      end

      def accumulate(event)
        @timestamp = event.delta[:timestamp] if event.respond_to?(:delta) && event.delta.is_a?(Hash) && event.delta[:timestamp]

        case event.type
        when :text_start
          blocks[event.content_index] = {
            type: "text",
            text: ""
          }
          blocks[event.content_index][:text] += event.delta
        when :text_delta, :text_end
          blocks[event.content_index][:text] += event.delta
        when :tool_start
          blocks[event.content_index] = {
            type: "tool_use",
            id: event.id,
            name: event.name,
            input: event.delta.to_s
          }
        when :tool_delta, :tool_end
          blocks[event.content_index][:input] += event.delta
        when :message_start
          message_hash.merge!(event.delta)
        when :reasoning_start
          blocks[event.content_index] = {
            type: "reasoning",
            reasoning: "",
            signature: ""
          }
          blocks[event.content_index][:reasoning] += event.delta
          blocks[event.content_index][:signature] += event.signature
        when :reasoning_delta, :reasoning_end
          blocks[event.content_index][:reasoning] += event.delta
          blocks[event.content_index][:signature] += event.signature
        when :message_delta
          message_hash.merge!(event.delta)
          assign_usage(event.usage) unless event.usage.empty?
        end
      end

      def empty_partial
        PartialAssistantMessage.new(timestamp: @timestamp)
      end

      def partial_message
        PartialAssistantMessage.new(partial_result)
      end

      def partial_result
        ensure_timestamp!

        message_hash.merge(
          timestamp: @timestamp,
          content: serialized_blocks
        )
      end

      def assign_usage(usage)
        @usage_hash = normalized_usage(usage)
      end

      def normalized_usage(usage)
        usage = DEFAULT_USAGE.merge(symbolize_keys(usage).slice(*DEFAULT_USAGE.keys))
        usage[:total] = usage[:input] + usage[:cache_write] + usage[:cache_read] + usage[:output]
        usage
      end

      def serialized_blocks
        blocks.map do |content_block|
          next content_block unless content_block[:type] == "tool_use"

          content_block.merge(input: LlmGateway::Utils.deep_symbolize_keys(parse_tool_input(content_block[:input])))
        end
      end

      def parse_tool_input(input)
        return {} if input.nil? || input.empty?

        JSON.parse(input)
      rescue JSON::ParserError
        {}
      end

      def symbolize_keys(hash)
        hash.to_h.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
      end

      def string_value(value)
        value.nil? ? "" : value.to_s
      end

      def ensure_timestamp!
        @timestamp ||= (Time.now.to_f * 1000).to_i
      end
    end
  end
end
