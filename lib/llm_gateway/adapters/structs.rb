require "dry-struct"
require "dry-types"

module Types
  include Dry.Types()
end

class BaseStruct < Dry::Struct
  transform_keys(&:to_sym)
end

class AssistantStreamEvent < BaseStruct
  EventType = Types::Coercible::Symbol.enum(:text_start, :text_delta, :text_end, :tool_start, :tool_delta, :tool_end, :tool_result_start, :tool_result_delta, :tool_result_end, :reasoning_start, :reasoning_delta, :reasoning_end)

  attribute :type, EventType
  attribute :delta, Types::Coercible::String.default { "" }
  attribute :content_index, Types::Integer
end


class AssistantToolStartEvent < AssistantStreamEvent
  attribute :id, Types::String
  attribute :name, Types::String
  attribute :tool_type, Types::String.enum("tool_use", "server_tool_use")
  attribute :content_index, Types::Integer
end

class AssistantToolResultStartEvent < AssistantStreamEvent
  attribute :tool_use_id, Types::String
  attribute :name, Types::String
  attribute :content_index, Types::Integer
end

class AssistantStreamReasoningEvent < AssistantStreamEvent
  attribute :signature, Types::Coercible::String.default { "" }
  attribute :content_index, Types::Integer
end

class AssistantStreamMessageEvent < BaseStruct
  EventType = Types::Coercible::Symbol.enum(:message_start, :message_delta, :message_end)

  attribute :type, EventType
  attribute :delta, Types::Coercible::Hash.default { {} }
  attribute :usage_increment, Types::Coercible::Hash.default { {} }
end

class TextContent < BaseStruct
  attribute :type, Types::String.enum("text")
  attribute :text, Types::String

  def to_h
    {
      type: type,
      text: text
    }
  end
end

class ReasoningContent < BaseStruct
  attribute :type, Types::String.enum("reasoning")
  attribute :reasoning, Types::String
  attribute? :signature, Types::String.optional

  def to_h
    result = {
      type: type,
      reasoning: reasoning
    }
    result[:signature] = signature unless signature.nil?
    result
  end
end

class ToolCall < BaseStruct
  attribute :id, Types::String
  attribute :type, Types::String.enum("tool_use")
  attribute :name, Types::String
  attribute :input, Types::Hash

  def to_h
    {
      id: id,
      type: type,
      name: name,
      input: input
    }
  end
end

class ServerToolCall < ToolCall
  attribute :type, Types::String.enum("server_tool_use")
end

class ToolResult < BaseStruct
  attribute :type, Types::String
  attribute :tool_use_id, Types::String
  attribute :content, Types::Any

  def to_h
    {
      type: type,
      tool_use_id: tool_use_id,
      content: content
    }
  end
end

class ServerToolResult < ToolResult
  attribute :type, Types::String.enum("server_tool_result")
end

class AssistantMessage < BaseStruct
  ContentBlock =
    Types.Instance(TextContent) |
    Types.Instance(ReasoningContent) |
    Types.Instance(ToolCall) |
    Types.Instance(ServerToolCall) |
    Types.Instance(ToolResult) |
    Types.Instance(ServerToolResult)

  attribute :id, Types::String
  attribute :model, Types::String
  attribute :usage, Types::Hash
  attribute :role, Types::String.enum("assistant")
  attribute :stop_reason, Types::String.enum("stop", "length", "tool_use", "toolUse", "error", "aborted")
  attribute :provider, Types::String
  attribute :api, Types::String
  attribute? :error_message, Types::String.optional
  attribute :content, Types::Array.of(ContentBlock)

  def self.new(attributes)
    attrs = attributes.to_h.transform_keys(&:to_sym)
    attrs[:content] = Array(attrs[:content]).map { |block| build_content_block(block) }
    super(attrs)
  end

  def to_h
    result = {
      id: id,
      model: model,
      usage: usage,
      role: role,
      stop_reason: stop_reason,
      provider: provider,
      api: api,
      content: content.map(&:to_h)
    }
    result[:error_message] = error_message unless error_message.nil?
    result
  end

  def self.build_content_block(block)
    return block if block.is_a?(TextContent) || block.is_a?(ReasoningContent) || block.is_a?(ToolCall) || block.is_a?(ServerToolCall) || block.is_a?(ToolResult) || block.is_a?(ServerToolResult)

    case block[:type] || block["type"]
    when "text"
      TextContent.new(block)
    when "reasoning"
      ReasoningContent.new(block)
    when "thinking"
      ReasoningContent.new(type: "reasoning", reasoning: block[:thinking] || block["thinking"] || block[:reasoning] || block["reasoning"], signature: block[:signature] || block["signature"])
    when "tool_use"
      ToolCall.new(block)
    when "server_tool_use"
      ServerToolCall.new(block)
    else
      type = block[:type] || block["type"]
      return ServerToolResult.new(block) if type == "server_tool_result"
      return ToolResult.new(block) if type&.end_with?("_tool_result")
      raise ArgumentError, "Unsupported content block type: #{block[:type] || block['type']}"
    end
  end

  private_class_method :build_content_block
end
