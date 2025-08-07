# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Claude
      class InputMapper
        extend LlmGateway::FluentMapper

        map :messages do |_, value|
          value.map do |msg|
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

        map :system do |_, value|
          if !value || value.empty?
            nil
          elsif value.length == 1 && value.first[:role] == "system"
            # If we have a single system message, convert to Claude format
            [ { type: "text", text: value.first[:content] } ]
          else
            # For multiple messages or non-standard format, pass through
            value
          end
        end

        map :tools do |_, value|
          value
        end
      end
    end
  end
end
