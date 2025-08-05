
class FileSearchTool < LlmGateway::Tool
  name 'execute_bash_command'
  description 'Execute bash commands for file searching and directory exploration'
  input_schema({
    type: 'object',
    properties: {
      command: { type: 'string', description: 'The bash command to execute' },
      explanation: { type: 'string', description: 'Explanation of what the command does' }
    },
    required: [ 'command', 'explanation' ]
  })

  def execute(input, login = nil)
    command = input[:command]
    explanation = input[:explanation]

    puts "Executing: #{command}"
    puts "Purpose: #{explanation}\n\n"

    begin
      result = `#{command} 2>&1`
      if $?.success?
        result.empty? ? "Command completed successfully (no output)" : result
      else
        "Error: #{result}"
      end
    rescue => e
      "Error executing command: #{e.message}"
    end
  end
end
