# frozen_string_literal: true

require "securerandom"
require "time"

module LlmGateway
  module Agents
    class InMemorySessionManager
      MESSAGE_QUEUED = :queued
      MESSAGE_STARTED = :started
      QUEUES = [ :steer, :follow_up, :next_turn ].freeze
      DRAIN_MODES = [ :one_at_a_time, :all ].freeze

      attr_reader :session_id, :session_start

      def initialize(session_id = nil)
        @state = :idle
        @session_id = session_id
        @message_queues = Hash.new { |hash, key| hash[key] = [] }
      end

      def busy!
        @state = :busy
      end

      def idle!
        @state = :idle
      end

      def drain_message_queue(queue = :next_turn, mode: :all)
        messages = queued_messages(queue, mode)
        messages.each { |message| push_message(message) }
        messages
      end

      def queued_messages?(queue = :next_turn)
        @message_queues[validate_queue!(queue)].any?
      end

      def push_message_to_queue(message, queue = :next_turn)
        @message_queues[validate_queue!(queue)] << message
      end

      def busy?
        @state == :busy
      end

      def idle?
        @state == :idle
      end

      def validate_queue!(queue)
        queue = queue.to_sym
        raise ArgumentError, "Invalid queue mode: #{queue}" unless QUEUES.include?(queue)

        queue
      end

      def validate_drain_mode!(mode)
        mode = mode.to_sym
        raise ArgumentError, "Invalid queue drain mode: #{mode}" unless DRAIN_MODES.include?(mode)

        mode
      end

      def start_or_enqueue_user_message(payload, queue: :next_turn)
        if busy?
          push_message_to_queue(payload, queue)
          MESSAGE_QUEUED
        else
          yield if block_given?
          push_message(payload)
          busy!
          MESSAGE_STARTED
        end
      end

      def push_message(payload)
        payload = payload.deep_symbolize_keys

        push_entry(
          type: "message",
          usage: message_usage(payload),
          data: payload,
        )
      end

      def push_entry(entry)
        id = SecureRandom.uuid
        new_entry = {
          id: id,
          parent_id: parent_id_for_new_entry,
          timestamp: Time.now.iso8601,
          **entry
        }

        persist_entry(new_entry)
        new_entry
      end

      def active_messages
        active_message_events.map { |event| event[:data] }
      end

      def last_message_id
        message_events.last&.dig(:id)
      end

      def last_model_used
        events.reverse.find { |event| event[:type] == "model_change" }&.dig(:model_id)
      end

      def last_reasoning_level_used
        events.reverse.find { |event| event[:type] == "reasoning_change" }&.dig(:reasoning)
      end

      def events_until(event_id)
        index = events.index { |event| event[:id] == event_id }
        raise ArgumentError, "Event not found in session: #{event_id}" unless index

        events[0..index]
      end

      def events
        @events ||= [ new_session_event ]
      end

      def build_model_input_messages
        return active_messages unless last_compaction_entry

        [ last_compaction_entry[:data], *active_messages ]
      end

      def total_tokens
        entry = active_message_events.reverse.find { |event| event.dig(:usage, :total_tokens) }
        entry&.dig(:usage, :total_tokens) || 0
      end

      def last_assistant_message_at
        entry = active_message_events.reverse.find { |event| event.dig(:data, :role) == "assistant" }
        Time.parse(entry[:timestamp]) if entry
      end

      def compaction(adapter)
        response = adapter.stream(
          active_messages,
          system: "Summarize the conversation so far for future context.",
          tools: []
        )
        message = response.to_h

        push_entry(
          type: "compaction",
          usage: message_usage(message),
          data: message
        )
      end

      private

      def queued_messages(queue, mode)
        queue = validate_queue!(queue)
        case validate_drain_mode!(mode)
        when :one_at_a_time
          message = @message_queues[queue].shift
          message ? [ message ] : []
        when :all
          @message_queues[queue].shift(@message_queues[queue].length)
        end
      end

      def parent_id_for_new_entry
        events.length.positive? ? events.last[:id] : nil
      end

      def message_events
        events.select { |event| event[:type] == "message" }
      end

      def active_message_events
        compaction_event = last_compaction_entry
        return message_events unless compaction_event

        compaction_index = events.index(compaction_event)
        events[(compaction_index + 1)..].select { |event| event[:type] == "message" }
      end

      def last_compaction_entry
        events.reverse.find { |event| event[:type] == "compaction" }
      end

      def message_usage(message)
        usage = message[:usage] || message["usage"]
        return {} unless usage

        usage.transform_keys(&:to_sym)
      end

      def persist_entry(entry)
        attributes = {
          session_id: @session_id,
          position: next_position,
          id: entry[:id],
          parent_id: entry[:parent_id],
          timestamp: entry[:timestamp],
          type: entry[:type],
          usage: entry[:usage],
          data: entry[:data]
        }

        events << entry
        attributes
      end

      def next_position
        events.length
      end

      def new_session_event
        @session_id ||= SecureRandom.uuid
        @session_start = Time.now.strftime("%Y%m%d_%H%M%S")
        { type: "session", id: session_id, timestamp: session_start }
      end
    end
  end
end
