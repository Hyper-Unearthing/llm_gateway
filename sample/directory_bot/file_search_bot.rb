require_relative 'file_search_tool'
require_relative 'file_search_prompt'
require 'debug'

# Bash File Search Assistant using LlmGateway architecture

class FileSearchBot
  def initialize(model, api_key)
    @transcript = []
    @model = model
    @api_key = api_key
  end

  def query(input)
    process_query(input)
  end

  private

  def process_query(query)
    # Add user message to transcript
    @transcript << { role: 'user', content: [ { type: 'text', text: query } ] }

    begin
      prompt = FileSearchPrompt.new(@model, @transcript, @api_key)
      result = prompt.post
      process_response(result[:choices][0][:content])
    rescue => e
      puts "Error: #{e.message}"
      puts "Backtrace: #{e.backtrace.join("\n")}"
      puts "I give up as bot"
    end
  end

  def process_response(response)
    # Add assistant response to transcript
    @transcript << { role: 'assistant', content: response }

    response.each do |message|
      if message[:type] == 'text'
        puts "\nBot: #{message[:text]}\n"
      elsif message[:type] == 'tool_use'
        result = handle_tool_use(message)

        # Add tool result to transcript
        tool_result = {
          type: 'tool_result',
          tool_use_id: message[:id],
          content: result
        }
        @transcript << { role: 'user', content: [ tool_result ] }

        # Continue conversation with tool result
        follow_up_prompt = FileSearchPrompt.new(@model, @transcript, @api_key)
        follow_up = follow_up_prompt.post

        process_response(follow_up[:choices][0][:content]) if follow_up[:choices][0][:content]
      end
    end
  end

  def handle_tool_use(message)
    if message[:name] == 'execute_bash_command'
      tool = FileSearchTool.new
      tool.execute(message[:input])
    else
      "Unknown tool: #{message[:name]}"
    end
  rescue StandardError => e
    "Error executing tool: #{e.message}"
  end
end
