# frozen_string_literal: true

require_relative "message_mapper"

module LlmGateway
  module Adapters
    module Claude
      class InputMapper
        def self.map(data)
          {
            messages: map_messages(data[:messages]),
            response_format: data[:response_format],
            tools: data[:tools],
            system: map_system(data[:system])
          }
        end

        private

        def self.map_messages(messages)
          return messages unless messages

          messages.map do |msg|
            msg = msg.merge(role: "user") if msg[:role] == "developer"

            content = if msg[:content].is_a?(Array)
                msg[:content].map do |content|
                  MessageMapper.map_content(content)
                end
            else
              [ MessageMapper.map_content(msg[:content]) ]
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
      end
    end
  end
end
