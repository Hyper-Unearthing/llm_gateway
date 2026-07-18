# frozen_string_literal: true

require_relative "tool"
require_relative "agents/event"

module LlmGateway
  class Prompt
    class_attribute :adapter, :model, :reasoning
    class_attribute :before_execute_callbacks, :after_execute_callbacks, instance_accessor: false, default: []
    attr_accessor :cache_key, :cache_retention

    def self.before_execute(*methods, &block)
      self.before_execute_callbacks += methods
      self.before_execute_callbacks += [ block ] if block_given?
    end

    def self.after_execute(*methods, &block)
      self.after_execute_callbacks += methods
      self.after_execute_callbacks += [ block ] if block_given?
    end

    def initialize(adapter: nil, model: nil, reasoning: nil, cache_key: nil, cache_retention: nil)
      @adapter = adapter || self.class.adapter
      @model = model || self.class.model
      @reasoning = reasoning || self.class.reasoning
      @cache_key = cache_key
      @cache_retention = cache_retention
    end

    def run(adapter: nil, model: nil, reasoning: nil, **options, &block)
      # Resolve the prompt once so dynamic or expensive prompt builders are not
      # evaluated multiple times during a single run.
      input = prompt

      run_callbacks(:before_execute, input)

      response = run_tool_loop(input, adapter: resolved_adapter(adapter), model: model, reasoning: reasoning, **options, &block)

      run_callbacks(:after_execute, response)

      response
    end

    def stream(input = prompt, adapter: nil, model: nil, reasoning: nil, **options, &block)
      stream_adapter = resolved_adapter(adapter)
      stream_options = default_stream_options(model: model, reasoning: reasoning).merge(options)

      stream_adapter.stream(input, **stream_options, &block)
    end

    def self.tools
      const_defined?(:TOOLS, false) ? self::TOOLS : []
    end

    def self.find_tool(name)
      tools.find { |tool| tool.tool_name == name }
    end

    def tools
      self.class.tools.map(&:definition)
    end

    def system_prompt
      nil
    end

    protected

    def execute_tool_requests(requests:, assistant_message: nil, session_event: nil)
      Agents::Event::ToolResultMessage.new(content: yield(requests))
    end

    private

    def find_and_execute_tool(tool_content_block, tool_call_id: nil, **kwargs)
      tool_call_id ||= tool_content_block.id
      tool_name = tool_content_block.name
      tool_input = tool_content_block.input
      tool_class = self.class.find_tool(tool_name)

      begin
        if tool_class
          result = execute_tool(tool_class, tool_input, tool_call_id: tool_call_id, **kwargs)
          return result if result.is_a?(Agents::Event::ToolCallResult)

          raise TypeError, "Tool #{tool_name} returned #{result.class}; expected LlmGateway::Agents::Event::ToolCallResult"
        end

        build_tool_call_result(tool_call_id, "Unknown tool: #{tool_name}")
      rescue StandardError => e
        build_tool_call_result(tool_call_id, "Error executing tool: #{e.message}")
      end
    end

    def execute_tool(tool_class, tool_input, tool_call_id:, **_kwargs)
      tool_class.new.execute(tool_input, tool_use_id: tool_call_id)
    end

    def build_tool_call_result(tool_use_id, content)
      Agents::Event::ToolCallResult.new(
        tool_use_id: tool_use_id,
        content: content
      )
    end

    def run_tool_requests(requests, **kwargs)
      requests.map { |request| find_and_execute_tool(request, **kwargs) }
    end

    def run_tool_loop(input, adapter: nil, model: nil, reasoning: nil, **options, &block)
      response = stream(input, adapter: adapter, model: model, reasoning: reasoning, **options, &block)

      while tool_requests(response).any?
        input = prompt_with_tool_results(input, response, tool_requests(response))
        response = stream(input, adapter: adapter, model: model, reasoning: reasoning, **options, &block)
      end

      response
    end

    def tool_requests(response)
      return [] unless response.respond_to?(:content)

      response.content.select { |content| content.respond_to?(:type) && content.type == "tool_use" }
    end

    def prompt_with_tool_results(input, response, requests)
      messages = input.is_a?(Array) ? input.dup : [ { role: "user", content: input } ]
      messages << response.to_h

      tool_result_message = execute_tool_requests(
        requests: requests,
        assistant_message: response,
        session_event: nil
      ) do |requests_to_execute|
        run_tool_requests(requests_to_execute)
      end
      messages << tool_result_message.to_h if tool_result_message.any?
      messages
    end

    def default_stream_options(model: nil, reasoning: nil)
      {
        tools: tools,
        system: system_prompt,
        model: resolved_model(model),
        reasoning: resolved_reasoning(reasoning),
        cache_key: cache_key,
        cache_retention: cache_retention
      }.compact
    end

    def resolved_adapter(adapter)
      adapter || self.adapter
    end

    def resolved_model(model)
      model || self.model
    end

    def resolved_reasoning(reasoning)
      reasoning || self.reasoning
    end

    def run_callbacks(callback_type, *args)
      self.class.public_send("#{callback_type}_callbacks").each do |callback|
        case callback
        when Proc
          instance_exec(*args, &callback)
        when Symbol, String
          public_send(callback, *args)
        end
      end
    end
  end
end
