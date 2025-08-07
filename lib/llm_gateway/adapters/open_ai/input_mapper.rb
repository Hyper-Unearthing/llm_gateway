# frozen_string_literal: true

module LlmGateway
  module Adapters
    module OpenAi
      class InputMapper < LlmGateway::Adapters::Groq::InputMapper
        map :messages do |_, value|
          value.map do |msg|
            if msg[:content].is_a?(Array)
              results = []

              # Check what content types we have
              text_content = msg[:content].select { |c| c[:type] == "text" || c.is_a?(String) }
              tool_uses = msg[:content].select { |c| c[:type] == "tool_use" }
              tool_results = msg[:content].select { |c| c[:type] == "tool_result" }
              files = msg[:content].select { |c| c[:type] == "file" }

              # If we have text and/or files but no tools, combine them in one message
              if (text_content.any? || files.any?) && tool_uses.empty? && tool_results.empty?
                combined_content = []

                # Add text content
                text_content.each do |c|
                  combined_content << {
                    type: "text",
                    text: c.is_a?(String) ? c : c[:text]
                  }
                end

                # Add file content
                files.each do |file|
                  combined_content << {
                    type: "file",
                    file: {
                      file_data: "data:application/pdf;base64,#{Base64.encode64(file[:data])}",
                      filename: file[:name]
                    }
                  }
                end

                results << {
                  role: msg[:role],
                  content: combined_content
                }
              else
                # Handle tool messages separately (they need to be separate messages)
                if text_content.any?
                  results << { role: msg[:role], content: text_content.map { |c| c.is_a?(String) ? c : c[:text] }.join }
                end

                # Handle tool_use messages
                results << map_single(msg, with: :tool_usage) if tool_uses.any?

                # Handle tool_result messages
                tool_results.each do |content|
                  results << map_single(content, with: :tool_result_message)
                end

                # Handle file content separately if there are tools
                if files.any? && (tool_uses.any? || tool_results.any?)
                  files.each do |file|
                    results << {
                      role: msg[:role],
                      content: [ {
                        type: "file",
                        file: {
                          file_data: "data:application/pdf;base64,#{Base64.encode64(file[:data])}",
                          filename: file[:name]
                        }
                      } ]
                    }
                  end
                end
              end

              # Return results or original message if no special content found
              results.empty? ? msg : results
            else
              msg
            end
          end.flatten
        end

        map :system do |_, value|
          if !value || value.empty?
            []
          else
            value.map do |msg|
              msg[:role] == "system" ? msg.merge(role: "developer") : msg
            end
          end
        end
      end
    end
  end
end
