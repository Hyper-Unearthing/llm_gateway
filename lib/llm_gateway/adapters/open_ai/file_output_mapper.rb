# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAi
      class FileOutputMapper
        def self.map(data)
          bytes = data.delete(:bytes)
          data.delete(:object) # Didnt see much value in this only option is "file"
          data.delete(:status) # Deprecated so no need to pull through
          data.delete(:status_details)  # Deprecated so no need to pull through
          created_at = data.delete(:created_at)
          time = Time.at(created_at, in: "UTC")
          iso_format = time.iso8601(6)
          data.merge(
            size_bytes: bytes,
            downloadable: data[:purpose] != "user_data",
            mime_type: nil,
            created_at: iso_format # Claude api format, easier for human reading so kept it this way
          )
        end
      end
    end
  end
end
