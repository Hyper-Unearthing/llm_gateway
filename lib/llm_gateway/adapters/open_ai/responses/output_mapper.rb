# frozen_string_literal: true

require "base64"
require_relative "bidirectional_message_mapper"

module LlmGateway
  module Adapters
    module OpenAi
      module Responses
        class OutputMapper
          def self.map(data)
            {
              id: data[:id],
              model: data[:model],
              usage: data[:usage],
              choices: map_choices(data[:output])
            }
          end

          private

          def self.map_choices(choices)
            return [] unless choices
            message_mapper = BidirectionalMessageMapper.new(LlmGateway::DIRECTION_OUT)
            choices.map do |choice|
              content = if choice[:id].start_with?("fc_")
                {
                  id: choice[:id],
                  role: choice[:role] || "assistant", # tool call doesnt have a role apparently
                  content: [ message_mapper.map_content(choice) ].flatten
                }
              else
               content = message_mapper.map_content(choice)
               id = content.delete(:id)
               {
                 id: choice[:id] || id,
                 role: choice[:role],
                 content: [ content ].flatten
               }
              end
            end
          end
        end
      end
    end
  end
end
