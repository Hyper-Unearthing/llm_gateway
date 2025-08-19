# frozen_string_literal: true

require "base64"

module LlmGateway
  module Adapters
    module OpenAi
      class InputMapper < LlmGateway::Adapters::Groq::InputMapper
        def self.map(data)
          {
            messages: map_messages(data[:messages]),
            response_format: map_response_format(data[:response_format]),
            tools: map_tools(data[:tools]),
            system: map_system(data[:system])
          }
        end

        private

        def self.map_messages(messages)
          return messages unless messages

          # First, handle file transformations
          messages_with_files = messages.map do |msg|
            if msg[:content].is_a?(Array)
              content = msg[:content].map do |content|
                if content[:type] == "file"
                  # Map text/plain to application/pdf for OpenAI
                  media_type = content[:media_type] == "text/plain" ? "application/pdf" : content[:media_type]
                  {
                    type: "file",
                    file: {
                      filename: content[:name],
                      file_data: "data:#{media_type};base64,#{Base64.encode64(content[:data])}"
                    }
                  }
                else
                  content
                end
              end
              msg.merge(content: content)
            else
              msg
            end
          end.compact
          # Then apply parent's tool transformation logic
          super(messages_with_files)
        end

        def self.map_system(system)
          if !system || system.empty?
            []
          else
            system.map do |msg|
              msg[:role] == "system" ? msg.merge(role: "developer") : msg
            end
          end
        end
      end
    end
  end
end
