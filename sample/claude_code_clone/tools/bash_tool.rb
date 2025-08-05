class BashTool < LlmGateway::Tool
  name 'Bash'
  description 'Execute shell commands'
  input_schema({
    type: 'object',
    properties: {
      command: { type: 'string', description: 'Shell command to execute' },
      description: { type: 'string', description: 'Human-readable description' },
      timeout: { type: 'integer', description: 'Timeout in milliseconds' }
    },
    required: [ 'command' ]
  })

  def execute(input)
    command = input[:command]
    description = input[:description]
    timeout = input[:timeout] || 120000 # Default 2 minutes

    if description
      puts "Executing: #{command}"
      puts "Description: #{description}\n\n"
    else
      puts "Executing: #{command}\n\n"
    end

    begin
      # Convert timeout from milliseconds to seconds
      timeout_seconds = timeout / 1000.0

      # Use timeout command if available, otherwise use Ruby's timeout
      if system('which timeout > /dev/null 2>&1')
        result = `timeout #{timeout_seconds}s #{command} 2>&1`
        exit_status = $?
      else
        require 'timeout'
        result = Timeout.timeout(timeout_seconds) do
          `#{command} 2>&1`
        end
        exit_status = $?
      end

      if exit_status.success?
        result.empty? ? "Command completed successfully (no output)" : result
      else
        "Command failed with exit code #{exit_status.exitstatus}:\n#{result}"
      end

    rescue Timeout::Error
      "Command timed out after #{timeout_seconds} seconds"
    rescue => e
      "Error executing command: #{e.message}"
    end
  end
end
