# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Claude
      class FileOutputMapper
        def self.map(data)
          data.delete(:type) # Didnt see much value in this only option is "file"
          data.merge(
            expires_at: nil, # came from open ai api
            purpose: "user_data",  # came from open ai api
          )
        end
      end

      class OutputMapper
        def self.map(data)
          {
            id: data[:id],
            model: data[:model],
            usage: data[:usage],
            choices: map_choices(data)
          }
        end

        private

        def self.map_choices(data)
          message_mapper = BidirectionalMessageMapper.new(LlmGateway::DIRECTION_OUT)

          content = if data[:content].is_a?(Array)
              data[:content].map do |content|
                message_mapper.map_content(content)
              end
          else
            data[:content] ? [ message_mapper.map_content(data[:content]) ] : []
          end

          # Claude returns content directly at root level, not in a choices array
          # We need to construct the choices array from the full response data
          [ {
            content: content, # Use content directly from Claude response
            finish_reason: data[:stop_reason],
            role: "assistant"
          } ]
        end
      end
    end
  end
end
