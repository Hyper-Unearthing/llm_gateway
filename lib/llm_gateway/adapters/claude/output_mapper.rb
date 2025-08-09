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
          # Claude returns content directly at root level, not in a choices array
          # We need to construct the choices array from the full response data
          [ {
            content: data[:content] || [], # Use content directly from Claude response
            finish_reason: data[:stop_reason],
            role: "assistant"
          } ]
        end
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
          mapped_response.slice(:choices)[:choices]
        end

        def files
          results = raw_response[:content].filter { |content| content[:type] == "code_execution_tool_result" }
          results.map do |result|
            execution_results = result[:content][:content]
            execution_results.map { |er| { filename: nil }.merge(er.slice(:file_id)) }
          end.flatten
        end

        def cleaned_response
          @cleaned_response ||= begin
            filtered_choices = mapped_response[:choices].map do |choice|
              choice.merge(content: choice[:content].filter { |content| ![ "server_tool_use", "code_execution_tool_result" ].include? content[:type] }).compact
            end
            {
              id: mapped_response[:id],
              usage: mapped_response[:usage],
              model: mapped_response[:model],
              choices: filtered_choices
            }.merge
          end
        end

        private

        def mapped_response
          @mapped_response ||= begin
            OutputMapper.map(raw_response)
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
