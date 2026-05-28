# frozen_string_literal: true

module LlmGateway
  class Prompt
    UNSET = Object.new.freeze

    attr_accessor :provider, :model, :reasoning

    class << self
      def provider(value = UNSET)
        @provider = value unless value.equal?(UNSET)
        @provider
      end

      def provider=(value)
        @provider = value
      end

      def model(value = UNSET)
        @model = value unless value.equal?(UNSET)
        @model
      end

      def model=(value)
        @model = value
      end

      def reasoning(value = UNSET)
        @reasoning = value unless value.equal?(UNSET)
        @reasoning
      end

      def reasoning=(value)
        @reasoning = value
      end
    end

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
      subclass.provider = provider
      subclass.model = model
      subclass.reasoning = reasoning
    end

    def initialize(provider_arg = UNSET, model_arg = UNSET, provider: UNSET, model: UNSET, reasoning: UNSET)
      @provider = resolve_legacy_positional_configuration(provider, provider_arg, self.class.provider)
      @model = resolve_legacy_positional_configuration(model, model_arg, self.class.model)
      @reasoning = resolve_keyword_configuration(reasoning, self.class.reasoning)
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

    def stream(provider: UNSET, model: UNSET, reasoning: UNSET, **options)
      stream_provider = provider.equal?(UNSET) ? self.provider : provider
      stream_model = model.equal?(UNSET) ? self.model : model
      stream_reasoning = reasoning.equal?(UNSET) ? self.reasoning : reasoning
      options[:model] = stream_model if stream_model
      options[:reasoning] = stream_reasoning unless stream_reasoning.equal?(UNSET) || stream_reasoning.nil?

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

    def resolve_legacy_positional_configuration(keyword_value, positional_value, class_value)
      return keyword_value unless keyword_value.equal?(UNSET)
      return positional_value unless positional_value.equal?(UNSET) || positional_value.nil?

      class_value
    end

    def resolve_keyword_configuration(keyword_value, class_value)
      return keyword_value unless keyword_value.equal?(UNSET)

      class_value
    end

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
