require_relative 'file_search_tool'
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
          puts "\nBot: #{message[:text]}\n"
        when 'tool_use'
          puts "\nTool Usage: #{message[:name]}"
          # puts "Input: #{message[:input]}"
        when 'tool_result'
        # puts "Tool Result: #{message[:content]}"
        when 'error'
          puts "Error: #{message[:message]}"
        end
      end
    rescue => e
      puts "Error: #{e.message}"
      puts "Backtrace: #{e.backtrace.join("\n")}"
      puts "I give up as bot"
    end
  end
end
