require "fileutils"
require_relative "../../tool"
require_relative "tool_utils"

class WriteTool < LlmGateway::Tool
  # Pi adaptation notes:
  # - Keep Ruby bytesize in the success message rather than pi's JS string length; the byte count is more accurate for UTF-8 content.
  # - Do not add pi's pluggable operations, AbortSignal handling, render previews, or details metadata: those are UI/runtime extension concerns outside this tool contract.
  name "write"
  description "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories."
  input_schema({
    type: "object",
    properties: {
      path: { type: "string", description: "Path to the file to write (relative or absolute)" },
      content: { type: "string", description: "Content to write to the file" }
    },
    required: [ "path", "content" ]
  })

  def execute(input, tool_use_id:)
    path = input[:path] || input["path"]
    content = input[:content] || input["content"]

    absolute_path = ToolUtils.resolve_to_cwd(path)

    ToolUtils.with_file_mutation_lock(absolute_path) do
      FileUtils.mkdir_p(File.dirname(absolute_path))
      File.write(absolute_path, content)
    end

    tool_result("Successfully wrote #{content.bytesize} bytes to #{path}", tool_use_id: tool_use_id)
  rescue StandardError => e
    tool_result(e.message, tool_use_id: tool_use_id)
  end
end
