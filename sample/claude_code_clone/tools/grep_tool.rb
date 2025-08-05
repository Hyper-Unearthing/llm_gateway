class GrepTool < LlmGateway::Tool
  name 'Grep'
  description 'Search for patterns in files using regex'
  input_schema({
    type: 'object',
    properties: {
      pattern: { type: 'string', description: 'Regex pattern to search for' },
      path: { type: 'string', description: 'File or directory path' },
      output_mode: { 
        type: 'string',
        enum: ['content', 'files_with_matches', 'count'],
        description: 'Output mode: content, files_with_matches, or count'
      },
      glob: { type: 'string', description: 'File pattern filter (e.g., "*.rb")' },
      '-n': { type: 'boolean', description: 'Show line numbers' },
      '-i': { type: 'boolean', description: 'Case insensitive search' },
      '-C': { type: 'integer', description: 'Context lines around matches' }
    },
    required: ['pattern']
  })

  def execute(input)
    pattern = input[:pattern]
    path = input[:path] || '.'
    output_mode = input[:output_mode] || 'files_with_matches'
    glob = input[:glob]
    show_line_numbers = input['-n'] || false
    case_insensitive = input['-i'] || false
    context_lines = input['-C'] || 0

    # Build grep command
    cmd_parts = ['grep']
    
    # Add flags
    cmd_parts << '-r' unless File.file?(path) # Recursive for directories
    cmd_parts << '-n' if show_line_numbers && output_mode == 'content'
    cmd_parts << '-i' if case_insensitive
    cmd_parts << "-C#{context_lines}" if context_lines > 0 && output_mode == 'content'
    
    # Output mode flags
    case output_mode
    when 'files_with_matches'
      cmd_parts << '-l'
    when 'count'
      cmd_parts << '-c'
    end

    # Add pattern and path
    cmd_parts << "'#{pattern}'"
    
    # Handle glob pattern
    if glob
      if File.directory?(path)
        cmd_parts << "#{path}/**/*"
        # Use shell globbing with find for better glob support
        find_cmd = "find #{path} -name '#{glob}' -type f"
        files_result = `#{find_cmd} 2>/dev/null`
        if files_result.empty?
          return "No files found matching pattern '#{glob}' in #{path}"
        end
        
        # Run grep on each matching file
        files = files_result.strip.split("\n")
        results = []
        
        files.each do |file|
          grep_cmd = cmd_parts[0..-2].join(' ') + " '#{pattern}' '#{file}'"
          result = `#{grep_cmd} 2>/dev/null`
          results << result unless result.empty?
        end
        
        return results.empty? ? "No matches found" : results.join("\n")
      else
        cmd_parts << path
      end
    else
      cmd_parts << path
    end

    command = cmd_parts.join(' ')
    
    begin
      puts "Executing: #{command}"
      result = `#{command} 2>&1`
      exit_status = $?

      if exit_status.success?
        if result.empty?
          "No matches found"
        else
          case output_mode
          when 'content'
            result
          when 'files_with_matches'
            result
          when 'count'
            result
          else
            result
          end
        end
      elsif exit_status.exitstatus == 1
        # grep returns 1 when no matches found, which is normal
        "No matches found"
      else
        "Error: #{result}"
      end

    rescue => e
      "Error executing grep: #{e.message}"
    end
  end
end