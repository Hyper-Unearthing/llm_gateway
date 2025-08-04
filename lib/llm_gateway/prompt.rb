# frozen_string_literal: true

module LlmGateway
  class Prompt
    attr_reader :model

    def self.before_execute(*methods, &block)
      before_execute_callbacks.concat(methods)
      before_execute_callbacks << block if block_given?
    end

    def self.after_execute(*methods, &block)
      after_execute_callbacks.concat(methods)
      after_execute_callbacks << block if block_given?
    end

    def self.before_execute_callbacks
      @before_execute_callbacks ||= []
    end

    def self.after_execute_callbacks
      @after_execute_callbacks ||= []
    end

    def self.inherited(subclass)
      super
      subclass.instance_variable_set(:@before_execute_callbacks, before_execute_callbacks.dup)
      subclass.instance_variable_set(:@after_execute_callbacks, after_execute_callbacks.dup)
    end

    def initialize(model)
      @model = model
    end

    def run
      run_callbacks(:before_execute, prompt)

      response = post

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

    def post
      LlmGateway::Client.chat(model, prompt, tools: tools, system: system_prompt)
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
