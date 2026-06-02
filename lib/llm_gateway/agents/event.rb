# frozen_string_literal: true

require_relative "../adapters/structs"

module LlmGateway
  module Agents
    module Event
      AgentEventType = Types::Coercible::Symbol.enum(
        :agent_start,
        :turn_start,
        :message_start,
        :message_update,
        :message_end,
        :tool_execution_start,
        :tool_execution_end,
        :turn_end,
        :agent_end
      )

      StreamEvent =
        Types.Instance(AssistantStreamEvent) |
        Types.Instance(AssistantStreamMessageEvent) |
        Types.Instance(AssistantStreamMessageEndEvent)

      ToolParameters = Types::Hash.schema(
        id: Types::String,
        type: Types::String.enum("tool_use"),
        name: Types::String,
        input: Types::Hash
      )

      class ToolCallResult < ::BaseStruct
        attribute :type, Types::Coercible::Symbol.enum(:tool_result)
        attribute :tool_use_id, Types::String
        attribute :content, Types::Any

        def to_h
          {
            type: type.to_s,
            tool_use_id: tool_use_id,
            content: content
          }
        end

        def dig(*keys)
          to_h.dig(*keys)
        end
      end

      class Base < ::BaseStruct
        attribute :type, AgentEventType

        def to_h
          {
            type: type
          }
        end
      end

      class AgentStart < Base
        attribute :type, Types::Coercible::Symbol.default(:agent_start).enum(:agent_start)
      end

      class TurnStart < Base
        attribute :type, Types::Coercible::Symbol.default(:turn_start).enum(:turn_start)
      end

      class MessageStart < Base
        attribute :type, Types::Coercible::Symbol.default(:message_start).enum(:message_start)
      end

      class MessageUpdate < Base
        attribute :type, Types::Coercible::Symbol.default(:message_update).enum(:message_update)
        attribute :stream_event, StreamEvent
      end

      class MessageEnd < Base
        attribute :type, Types::Coercible::Symbol.default(:message_end).enum(:message_end)
        attribute :message, Types.Instance(AssistantMessage)
      end

      class ToolExecutionStart < Base
        attribute :type, Types::Coercible::Symbol.default(:tool_execution_start).enum(:tool_execution_start)
        attribute :parameters, ToolParameters
      end

      class ToolExecutionEnd < Base
        attribute :type, Types::Coercible::Symbol.default(:tool_execution_end).enum(:tool_execution_end)
        attribute :parameters, ToolParameters
        attribute :result, ToolCallResult
      end

      class TurnEnd < Base
        attribute :type, Types::Coercible::Symbol.default(:turn_end).enum(:turn_end)
        attribute :message, Types.Instance(AssistantMessage)
        attribute :tool_results, Types::Array.of(Types.Instance(::ToolResult))
      end

      class AgentEnd < Base
        attribute :type, Types::Coercible::Symbol.default(:agent_end).enum(:agent_end)
        attribute :messages, Types::Array.of(Types::Hash)
      end
    end
  end
end
