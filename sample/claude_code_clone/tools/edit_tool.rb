class EditTool < LlmGateway::Tool
  name 'Edit'
  description 'Modify existing files by replacing specific text strings'
  input_schema({
    type: 'object',
    properties: {
      file_path: { type: 'string', description: 'Absolute path to file to modify' },
      old_string: { type: 'string', description: 'Exact text to replace' },
      new_string: { type: 'string', description: 'Replacement text' },
      replace_all: { type: 'boolean', description: 'Replace all occurrences (default: false)' }
    },
    required: [ 'file_path', 'old_string', 'new_string' ]
  })

  def execute(input)
    file_path = input[:file_path]
    old_string = input[:old_string]
    new_string = input[:new_string]
    replace_all = input[:replace_all] || false

    # Validate file exists
    unless File.exist?(file_path)
      return "Error: File not found at #{file_path}"
    end

    # Read file content
    begin
      content = File.read(file_path)
    rescue => e
      return "Error reading file: #{e.message}"
    end

    # Check if old_string exists in file
    unless content.include?(old_string)
      return "Error: Text '#{old_string}' not found in file"
    end

    # Perform replacement
    if replace_all
      updated_content = content.gsub(old_string, new_string)
      occurrences = content.scan(old_string).length
    else
      # Replace only first occurrence
      updated_content = content.sub(old_string, new_string)
      occurrences = 1
    end

    # Check if replacement would result in same content
    if content == updated_content
      return "Error: old_string and new_string are identical, no changes made"
    end

    # Write updated content back to file
    begin
      File.write(file_path, updated_content)
      "Successfully replaced #{occurrences} occurrence(s) in #{file_path}"
    rescue => e
      "Error writing file: #{e.message}"
    end
  end
end
