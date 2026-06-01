# frozen_string_literal: true

module LlmGateway
  class Prompt
    class_attribute :provider, :model, :reasoning
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

    def initialize(provider: nil, model: nil, reasoning: nil, cache_key: nil, cache_retention: nil)
      @provider = provider || self.class.provider
      @model = model || self.class.model
      @reasoning = reasoning || self.class.reasoning
      @cache_key = cache_key
      @cache_retention = cache_retention
    end

    def run(provider: nil, model: nil, reasoning: nil, **options, &block)
      # Resolve the prompt once so dynamic or expensive prompt builders are not
      # evaluated multiple times during a single run.
      input = prompt

      run_callbacks(:before_execute, input)

      response = run_tool_loop(input, provider: resolved_provider(provider), model: model, reasoning: reasoning, **options, &block)

      run_callbacks(:after_execute, response)

      response
    end

    def stream(input = prompt, provider: nil, model: nil, reasoning: nil, **options, &block)
      stream_provider = resolved_provider(provider)
      stream_options = default_stream_options(model: model, reasoning: reasoning).merge(options)

      stream_provider.stream(input, **stream_options, &block)
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

    private

    def find_and_execute_tool(tool_request)
      tool_name = tool_request.name
      tool_input = tool_request.input
      tool_class = self.class.find_tool(tool_name)

      result = begin
        if tool_class
          execute_tool(tool_class, tool_input)
        else
          "Unknown tool: #{tool_name}"
        end
      rescue StandardError => e
        "Error executing tool: #{e.message}"
      end
      ToolResult.new(
        type: "tool_result",
        tool_use_id: tool_request.id,
        content: result,
      )
    end

    def execute_tool(tool_class, tool_input)
      tool_class.new.execute(tool_input)
    end

    def run_tool_loop(input, provider: nil, model: nil, reasoning: nil, **options, &block)
      response = stream(input, provider: provider, model: model, reasoning: reasoning, **options, &block)

      while tool_requests(response).any?
        input = prompt_with_tool_results(input, response, tool_requests(response))
        response = stream(input, provider: provider, model: model, reasoning: reasoning, **options, &block)
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
      messages << {
        role: "user",
        content: requests.map { |request| find_and_execute_tool(request).to_h }
      }
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

    def resolved_provider(provider)
      provider || self.provider
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
