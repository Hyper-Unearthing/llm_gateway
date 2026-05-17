# frozen_string_literal: true

module LlmGateway
  module Adapters
    module Anthropic
      class FileOutputMapper
        def self.map(data)
          data.delete(:type) # Didnt see much value in this only option is "file"
          data.merge(
            expires_at: nil, # came from open ai api
            purpose: "user_data",  # came from open ai api
          )
        end
      end
    end
  end
end
