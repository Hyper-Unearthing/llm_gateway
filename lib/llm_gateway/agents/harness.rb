# frozen_string_literal: true

require_relative "event"
require_relative "../utils"

module LlmGateway
  module Agents
    class Harness < LlmGateway::Prompt
      COMPACTION_TOKEN_THRESHOLD = 180_000
      COMPACTION_IDLE_THRESHOLD_SECONDS = 60 * 60

      attr_reader :session_manager, :adapter, :default_queue_mode, :queue_drain_mode

      def initialize(session_manager, adapter:, cache_key: nil, cache_retention: nil)
        super(adapter:, cache_key:, cache_retention:)
        @session_manager = session_manager
        validate_adapter_model!(adapter, model)
        self.default_queue_mode = :follow_up
        self.queue_drain_mode = :all
      end

      def transcript
        session_manager.build_model_input_messages
      end
      alias :prompt :transcript

      def model
        runtime_configuration.model
      end

      def reasoning
        runtime_configuration.reasoning
      end

      def prompt_message(message, &block)
        enqueue_and_continue_if_idle(message, default_queue_mode, &block)
      end

      def steer_message(message, &block)
        enqueue_and_continue_if_idle(message, :steer, &block)
      end

      def follow_up_message(message, &block)
        enqueue_and_continue_if_idle(message, :follow_up, &block)
      end

      def default_queue_mode=(mode)
        @default_queue_mode = session_manager.validate_queue!(mode)
      end

      def queue_drain_mode=(mode)
        @queue_drain_mode = session_manager.validate_drain_mode!(mode)
      end

      def model=(definition)
        return model if model.equal?(definition)

        validate_adapter_model!(adapter, definition)
        session_manager.change_model(definition)
      end

      def reasoning=(level)
        return reasoning if reasoning == level

        session_manager.change_reasoning(level)
      end

      def change_adapter(new_adapter, model: nil)
        current_model = self.model
        if model.nil? && new_adapter.provider != "proxy" && new_adapter.provider != current_model.provider
          raise LlmGateway::Errors::ModelProviderMismatch,
            "Changing providers requires a model definition for the new provider"
        end

        candidate_model = model || current_model
        validate_adapter_model!(new_adapter, candidate_model)
        session_manager.change_model(candidate_model) unless candidate_model.equal?(current_model)
        @adapter = new_adapter
      end

      def adapter=(new_adapter)
        change_adapter(new_adapter)
      end

      def compact
        session_manager.compaction(adapter)
      end

      def stream(input = transcript, **options, &block)
        stream_options = {
          cache_key: cache_key,
          cache_retention: cache_retention
        }.compact.merge(options).merge(
          model: model,
          tools: tools,
          system: system_prompt,
          reasoning: reasoning
        )
        adapter.stream(input, **stream_options, &block)
      end

      def run(&block)
        emit(Event::AgentStart.new, &block)
        drain_queue(:steer)
        emit(Event::TurnStart.new, &block)
        emit(Event::MessageStart.new, &block)

        assistant_message = stream do |event|
          emit(Event::MessageUpdate.new(stream_event: event), &block)
        end

        persisted_message = session_manager.push_message(assistant_message.to_h)
        emit(Event::MessageEnd.new(message: assistant_message), &block)

        tool_request_blocks = tool_requests(assistant_message)
        tool_result_message = execute_tool_requests(
          requests: tool_request_blocks,
          assistant_message: assistant_message,
          session_event: persisted_message
        ) do |requests_to_execute|
          run_tool_requests(requests_to_execute, session_event: persisted_message, &block)
        end
        tool_results = tool_result_message.tool_results

        session_manager.push_message(tool_result_message.to_h) if tool_result_message.any?

        turn_end_event = Event::TurnEnd.new(message: assistant_message, tool_results: tool_results)
        emit(turn_end_event, &block)

        return run(&block) if tool_results.length.positive?

        if session_manager.queued_messages?(:follow_up)
          compact_if_needed
          return run(&block) if drain_queue(:follow_up).any?
        end

        emit(Event::AgentEnd.new(messages: []), &block)
        assistant_message
      end

      def continue(&block)
        raise RuntimeError, "Cannot continue a busy agent" if session_manager.busy?

        session_manager.busy!
        begin
          drain_queue(:steer)
          drain_queue(:follow_up)
          run(&block)
        ensure
          session_manager.idle!
        end
      end

      private

      def runtime_configuration
        session_manager.current_configuration
      end

      def validate_adapter_model!(candidate_adapter, candidate_model)
        unless candidate_adapter.respond_to?(:validate_model!)
          raise ArgumentError, "adapter must implement #validate_model!"
        end
        unless candidate_model
          raise LlmGateway::Errors::InvalidModelDefinition,
            "The session must have a model before constructing a harness"
        end

        candidate_adapter.validate_model!(candidate_model)
      end

      def enqueue_and_continue_if_idle(message, queue, &block)
        prepared_input = LlmGateway::Utils.deep_symbolize_keys(message)
        if session_manager.busy?
          session_manager.push_message_to_queue(prepared_input, queue)
          return
        end

        compact_if_needed
        session_manager.push_message_to_queue(prepared_input, queue)
        continue(&block)
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

      def run_tool_requests(requests, session_event:, &block)
        requests.map do |tool_content_block|
          parameters = tool_content_block.to_h
          emit(Event::ToolExecutionStart.new(parameters: parameters), &block)
          tool_result = find_and_execute_tool(tool_content_block, session_event: session_event)
          emit(Event::ToolExecutionEnd.new(parameters: parameters, result: tool_result), &block)
          tool_result
        end
      end

      def emit(event, &block)
        block&.call(event)
      end
    end
  end
end
