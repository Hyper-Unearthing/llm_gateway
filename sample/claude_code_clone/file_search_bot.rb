require_relative 'tools/file_search_tool'
require_relative 'file_search_prompt'
require_relative 'agent'
require 'debug'

# Bash File Search Assistant using LlmGateway architecture

class FileSearchBot
  def initialize(model, api_key)
    @agent = Agent.new(FileSearchPrompt, model, api_key)
  end

  def query(input)
    begin
      @agent.run(input) do |message|
        case message[:type]
        when 'text'
          puts "\n\e[32m•\e[0m #{message[:text]}"
        when 'tool_use'
          puts "\n\e[33m•\e[0m \e[36m#{message[:name]}\e[0m"
          if message[:input] && !message[:input].empty?
            puts "  \e[90m#{message[:input]}\e[0m"
          end
        when 'tool_result'
          if message[:content] && !message[:content].empty?
            content_preview = message[:content].to_s.split("\n").first(3).join("\n")
            if content_preview.length > 100
              content_preview = content_preview[0..97] + "..."
            end
            puts "  \e[90m#{content_preview}\e[0m"
          end
        when 'error'
          puts "\n\e[31m•\e[0m \e[91mError: #{message[:message]}\e[0m"
        end
      end
    rescue => e
      puts "\n\e[31m•\e[0m \e[91mError: #{e.message}\e[0m"
      puts "\e[90m  #{e.backtrace.first}\e[0m" if e.backtrace&.first
    end
  end
end
