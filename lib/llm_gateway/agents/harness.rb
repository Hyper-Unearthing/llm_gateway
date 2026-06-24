# frozen_string_literal: true

require_relative "event"
require_relative "../utils"

module LlmGateway
  module Agents
    class Harness < LlmGateway::Prompt
      COMPACTION_TOKEN_THRESHOLD = 180_000
      COMPACTION_IDLE_THRESHOLD_SECONDS = 60 * 60
      attr_accessor :provider
      attr_reader :session_manager, :default_queue_mode, :queue_drain_mode,
                  :model, :reasoning

      def initialize(session_manager, provider:, model: nil, reasoning: "high")
        @provider = provider
        super(provider: provider, model: model, reasoning: reasoning)
        @session_manager = session_manager
        sync_initial_configuration_events
        self.default_queue_mode = :next_turn
        self.queue_drain_mode = :all
      end

      def transcript
        session_manager.build_model_input_messages
      end
      alias :prompt :transcript

      def prompt_message(message, &block)
        enqueue_or_run_message(message, default_queue_mode, &block)
      end

      def steer_message(message, &block)
        enqueue_or_run_message(message, :steer, &block)
      end

      def follow_up_message(message, &block)
        enqueue_or_run_message(message, :follow_up, &block)
      end

      def next_turn_message(message, &block)
        enqueue_or_run_message(message, :next_turn, &block)
      end

      def default_queue_mode=(mode)
        @default_queue_mode = session_manager.validate_queue!(mode)
      end

      def queue_drain_mode=(mode)
        @queue_drain_mode = session_manager.validate_drain_mode!(mode)
      end

      def model=(model_id)
        return @model if @model == model_id

        @model = model_id
        publish_session_event(type: "model_change", model_id: model_id)
        @model
      end

      def reasoning=(level)
        return @reasoning if @reasoning == level

        @reasoning = level
        publish_session_event(type: "reasoning_change", reasoning: level)
        @reasoning
      end

      def compact
        session_manager.compaction(provider)
      end

      def run(&block)
        emit(Event::AgentStart.new, &block)
        drain_queue(:steer)
        emit(Event::TurnStart.new, &block)
        emit(Event::MessageStart.new, &block)

        assistant_message = stream do |event|
          emit(Event::MessageUpdate.new(stream_event: event), &block)
        end

        session_manager.push_message(assistant_message.to_h)
        emit(Event::MessageEnd.new(message: assistant_message), &block)

        tool_results = tool_requests(assistant_message).map do |message|
          parameters = message.to_h
          emit(Event::ToolExecutionStart.new(parameters: parameters), &block)
          tool_result = find_and_execute_tool(message)
          emit(Event::ToolExecutionEnd.new(parameters: parameters, result: tool_result), &block)
          tool_result
        end

        tool_result_content = tool_results.map(&:to_h)
        session_manager.push_message(
          role: "user",
          content: tool_result_content,
        ) unless tool_result_content.empty?

        turn_end_event = Event::TurnEnd.new(message: assistant_message, tool_results: tool_results)
        emit(turn_end_event, &block)

        if tool_results.length.positive?
          return run(&block)
        end

        if session_manager.queued_messages?(:follow_up)
          compact_if_needed
          return run(&block) if drain_queue(:follow_up).any?
        end

        emit(Event::AgentEnd.new(messages: []), &block)
        assistant_message
      end
      alias :continue   :run

      private

      def publish_session_event(type:, **attributes)
        session_manager.push_entry(type: type, **attributes)
      end

      def sync_initial_configuration_events
        publish_session_event(type: "model_change", model_id: model) if model && !session_manager.last_model_used
        if reasoning && !session_manager.last_reasoning_level_used
          publish_session_event(type: "reasoning_change", reasoning: reasoning)
        end
      end

      def enqueue_or_run_message(message, queue, &block)
        if session_manager.idle?
          drain_queue(:steer)
          drain_queue(:next_turn)
          drain_queue(:follow_up)
        end
        prepared_input = LlmGateway::Utils.deep_symbolize_keys(message)
        result = session_manager.start_or_enqueue_user_message(prepared_input, queue: queue) do
          compact_if_needed
        end
        return if result == session_manager.class::MESSAGE_QUEUED

        begin


          continue(&block)

          loop do
            break unless session_manager.queued_messages?(:next_turn)

            compact_if_needed
            drain_queue(:next_turn)
            continue(&block)
          end
        ensure
          session_manager.idle!
        end
      end

      def compact_if_needed
        compact if compaction_needed?
      end

      def compaction_needed?
        session_manager.total_tokens > COMPACTION_TOKEN_THRESHOLD || last_assistant_message_stale?
      end

      def last_assistant_message_stale?
        last_assistant_message_at = session_manager.last_assistant_message_at
        last_assistant_message_at && Time.now - last_assistant_message_at > COMPACTION_IDLE_THRESHOLD_SECONDS
      end

      def drain_queue(queue)
        session_manager.drain_message_queue(queue, mode: queue_drain_mode)
      end

      def emit(event, &block)
        return unless block

        block.call(event)
      end
    end
  end
end
