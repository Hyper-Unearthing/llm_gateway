# frozen_string_literal: true

require_relative "agents/event"

module LlmGateway
  class Tool
    def initialize(*_args, **_kwargs)
      # Empty constructor to allow subclasses to call super.
    end

    def self.name(value = nil)
      @name = value if value
      @name
    end

    def self.description(value = nil)
      @description = value if value
      @description
    end

    def self.input_schema(value = nil)
      @input_schema = value if value
      @input_schema
    end

    def self.cache(value = nil)
      @cache = value if value
      @cache
    end

    def self.definition
      {
        name: @name,
        description: @description,
        input_schema: @input_schema,
        cache_control: @cache ? { type: "ephemeral" } : nil
      }.compact
    end

    def self.tool_name
      definition[:name]
    end

    def tool_result(content, tool_use_id:)
      LlmGateway::Agents::Event::ToolCallResult.new(
        tool_use_id: tool_use_id,
        content: content
      )
    end

    def execute(input, tool_use_id:)
      raise NotImplementedError, "Subclasses must implement execute"
    end
  end
end
