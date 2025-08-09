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
      class OutputMapper < LlmGateway::Adapters::Groq::OutputMapper
      end

      class ResponseModel
        attr_reader :raw_response

        def initialize(response)
          @raw_response = response
        end

        def ==(other)
          cleaned_response == other
        end

        def [](key)
          cleaned_response[key]
        end

        def transcript
          raw_response[:output]
        end

        def files
          filtered_result = raw_response[:output].filter { |response| [ "message" ].include?(response[:type]) }
          filtered_result.map do |result|
            case result[:type]
            when "message"
              result[:content].map do |content|
                case content[:type]
                when "output_text"
                  content[:annotations].map do |annotation|
                    if annotation[:type] == "container_file_citation"
                      annotation.slice(:file_id, :filename)
                    end
                  end.compact if content[:annotations].any?
                end
              end.compact
            end
          end.flatten
        end

        def cleaned_response
          @cleaned_response ||= begin
            output = raw_response[:output].map do |result|
              case result[:type]
              when "message"
                result[:content].map do |content|
                  case content[:type]
                  when "output_text"
                    {
                      type: "text",
                      text: content[:text]
                    }
                  end
                end.compact
              when "function_call"
                {
                  id: result[:call_id],
                  type: "tool_use",
                  name: result[:name],
                  input: LlmGateway::Utils.deep_symbolize_keys(JSON.parse(result[:arguments]))
                }
              else
                nil
              end
            end.compact.flatten
            {
              choices: [ content: output ],
              model: raw_response[:model],
              id: raw_response[:id],
              usage: raw_response[:usage]
            }
          end
        end
      end


      class ResponsesMapper
        def self.map(data)
          ResponseModel.new(data)
        end
      end
    end
  end
end
