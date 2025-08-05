class ReadTool < LlmGateway::Tool
  name 'Read'
  description 'Read file contents with optional pagination'
  input_schema({
    type: 'object',
    properties: {
      file_path: { type: 'string', description: 'Absolute path to file' },
      limit: { type: 'integer', description: 'Number of lines to read' },
      offset: { type: 'integer', description: 'Starting line number' }
    },
    required: [ 'file_path' ]
  })

  def execute(input)
    file_path = input[:file_path]
    limit = input[:limit]
    offset = input[:offset] || 0

    # Validate file exists
    unless File.exist?(file_path)
      return "Error: File not found at #{file_path}"
    end

    # Check if it's a directory
    if File.directory?(file_path)
      return "Error: #{file_path} is a directory, not a file"
    end

    begin
      lines = File.readlines(file_path, chomp: true)

      # Apply offset
      if offset > 0
        if offset >= lines.length
          return "Error: Offset #{offset} exceeds file length (#{lines.length} lines)"
        end
        lines = lines[offset..-1]
      end

      # Apply limit
      if limit && limit > 0
        lines = lines[0, limit]
      end

      # Format output with line numbers (similar to cat -n)
      output = lines.each_with_index.map do |line, index|
        line_number = offset + index + 1
        "#{line_number.to_s.rjust(6)}→#{line}"
      end

      if output.empty?
        "File is empty or no lines in specified range"
      else
        output.join("\n")
      end

    rescue => e
      "Error reading file: #{e.message}"
    end
  end
end
