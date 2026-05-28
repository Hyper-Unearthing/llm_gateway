# frozen_string_literal: true

module LlmGateway
  class Prompt
    class_attribute :provider, :model, :reasoning
    class_attribute :before_execute_callbacks, :after_execute_callbacks, instance_accessor: false, default: []

    def self.before_execute(*methods, &block)
      self.before_execute_callbacks += methods
      self.before_execute_callbacks += [ block ] if block_given?
    end

    def self.after_execute(*methods, &block)
      self.after_execute_callbacks += methods
      self.after_execute_callbacks += [ block ] if block_given?
    end

    def initialize(provider: nil, model: nil, reasoning: nil)
      @provider = provider || self.class.provider
      @model = model || self.class.model
      @reasoning = reasoning || self.class.reasoning
    end

    def run
      run_callbacks(:before_execute, prompt)

      response = stream

      response_content = if respond_to?(:extract_response)
        extract_response(response)
      else
        response[:choices][0][:content]
      end

      result = if respond_to?(:parse_response)
        parse_response(response_content)
      else
        response_content
      end

      run_callbacks(:after_execute, response, response_content)

      result
    end

    def stream(provider: nil, model: nil, reasoning: nil, **options)
      stream_provider = provider || self.provider
      stream_model = model || self.model
      stream_reasoning = reasoning || self.reasoning
      options[:model] = stream_model if stream_model
      options[:reasoning] = stream_reasoning if stream_reasoning

      stream_provider.stream(prompt, tools: tools, system: system_prompt, **options)
    end

    def tools
      nil
    end

    def self.find_tool(tool_name)
      tools.find { |tool| tool.tool_name == tool_name }
    end

    def system_prompt
      nil
    end

    private

    def run_callbacks(callback_type, *args)
      callbacks = self.class.send("#{callback_type}_callbacks")
      callbacks.each do |callback|
        if callback.is_a?(Proc)
          instance_exec(*args, &callback)
        elsif callback.is_a?(Symbol) || callback.is_a?(String)
          send(callback, *args)
        end
      end
    end
  end
end
