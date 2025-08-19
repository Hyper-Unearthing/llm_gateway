# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Claude
      class InputMapper
        def self.map(data)
          {
            messages: map_messages(data[:messages]),
            response_format: data[:response_format],
            tools: map_tools(data[:tools]),
            system: map_system(data[:system])
          }
        end

        private

        def self.map_messages(messages)
          return messages unless messages

          messages.map do |msg|
            msg = msg.merge(role: "user") if msg[:role] == "developer"
            msg.slice(:role, :content)
            content = if msg[:content].is_a?(Array)
                msg[:content].map do |content|
                  if content[:type] == "file"
                    { type: "document", source: { data: content[:data], type: "text", media_type: content[:media_type] } }
                  else
                    content
                  end
                end
            else
              msg[:content]
            end
            {
              role: msg[:role],
              content: content
            }
          end
        end

        def self.map_system(system)
          if !system || system.empty?
            nil
          elsif system.length == 1 && system.first[:role] == "system"
            # If we have a single system message, convert to Claude format
            [ { type: "text", text: system.first[:content] } ]
          else
            # For multiple messages or non-standard format, pass through
            system
          end
        end

        def self.map_tools(tools)
          return tools unless tools

          tools.map do |tool|
            if tool[:type]
              case tool[:type]
              when "code_execution"
                { name: "code_execution", type: "code_execution_20250522" }
              else
                tool
              end
            else
              tool
            end
          end
        end
      end
    end
  end
end
