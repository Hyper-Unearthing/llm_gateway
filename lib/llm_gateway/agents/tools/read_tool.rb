require "base64"
require_relative "tool_utils"

class ReadTool < LlmGateway::Tool
  # Pi adaptation notes:
  # - Keep offset/limit schema as integer: gruv treats integer and number schemas equivalently for line counts.
  # - Do not add pi's image resize/model-omission behavior: current LLMs allow larger images than pi's conservative limit, and gruv tools do not receive model capability context.
  # - Do not add pi's compact read UI, pluggable operations, AbortSignal handling, or details metadata: those are UI/runtime extension concerns outside this tool contract.
  name "read"
  description "Read the contents of a file. Supports text files and images (jpg, png, gif, webp). Images are sent as attachments. For text files, output is truncated to #{ToolUtils::DEFAULT_MAX_LINES} lines or #{ToolUtils::DEFAULT_MAX_BYTES / 1024}KB (whichever is hit first). Use offset/limit for large files. When you need the full file, continue with offset until complete."
  input_schema({
    type: "object",
    properties: {
      path: { type: "string", description: "Path to the file to read (relative or absolute)" },
      offset: { type: "integer", description: "Line number to start reading from (1-indexed)" },
      limit: { type: "integer", description: "Maximum number of lines to read" }
    },
    required: [ "path" ]
  })

  IMAGE_TYPE_SNIFF_BYTES = 4100
  PNG_SIGNATURE = [ 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a ].freeze

  def execute(input)
    path = input[:path] || input["path"]
    offset = input[:offset] || input["offset"]
    limit = input[:limit] || input["limit"]

    absolute_path = ToolUtils.resolve_read_path(path)

    return "File not found: #{path}" unless File.exist?(absolute_path)
    return "Cannot read directory: #{path}" if File.directory?(absolute_path)
    return "File is not readable: #{path}" unless File.readable?(absolute_path)

    mime_type = detect_supported_image_mime_type_from_file(absolute_path)
    if mime_type
      data = Base64.strict_encode64(File.binread(absolute_path))
      return [
        { type: "text", text: "Read image file [#{mime_type}]" },
        { type: "image", data: data, media_type: mime_type }
      ]
    end

    content = File.read(absolute_path, mode: "r:bom|utf-8")
    all_lines = content.split("\n", -1)
    total_file_lines = all_lines.length

    start_line = [ 0, (offset || 1).to_i - 1 ].max
    return "Offset #{offset} is beyond end of file (#{all_lines.length} lines total)" if start_line >= all_lines.length

    selected_content = if limit
      end_line = [ start_line + limit.to_i, all_lines.length ].min
      all_lines[start_line...end_line].join("\n")
    else
      all_lines[start_line..].join("\n")
    end

    truncation = ToolUtils.truncate_head(selected_content)
    start_display = start_line + 1

    if truncation[:first_line_exceeds_limit]
      first_line_size = ToolUtils.format_size(all_lines[start_line].to_s.bytesize)
      return "[Line #{start_display} is #{first_line_size}, exceeds #{ToolUtils.format_size(ToolUtils::DEFAULT_MAX_BYTES)} limit. Use bash: sed -n '#{start_display}p' #{path} | head -c #{ToolUtils::DEFAULT_MAX_BYTES}]"
    end

    output = truncation[:content]

    if truncation[:truncated]
      end_display = start_display + truncation[:output_lines] - 1
      next_offset = end_display + 1
      suffix = if truncation[:truncated_by] == "lines"
        "[Showing lines #{start_display}-#{end_display} of #{total_file_lines}. Use offset=#{next_offset} to continue.]"
      else
        "[Showing lines #{start_display}-#{end_display} of #{total_file_lines} (#{ToolUtils.format_size(ToolUtils::DEFAULT_MAX_BYTES)} limit). Use offset=#{next_offset} to continue.]"
      end
      output = "#{output}\n\n#{suffix}"
    elsif limit && (start_line + limit.to_i) < all_lines.length
      next_offset = start_line + limit.to_i + 1
      remaining = all_lines.length - (start_line + limit.to_i)
      output = "#{output}\n\n[#{remaining} more lines in file. Use offset=#{next_offset} to continue.]"
    end

    output
  rescue StandardError => e
    "Error reading file: #{e.message}"
  end

  private

  def detect_supported_image_mime_type_from_file(path)
    detect_supported_image_mime_type(File.binread(path, IMAGE_TYPE_SNIFF_BYTES))
  end

  def detect_supported_image_mime_type(buffer)
    bytes = buffer.bytes
    return "image/jpeg" if jpeg?(bytes)
    return "image/png" if png?(bytes) && !animated_png?(bytes)
    return "image/gif" if ascii_at?(bytes, 0, "GIF")
    return "image/webp" if ascii_at?(bytes, 0, "RIFF") && ascii_at?(bytes, 8, "WEBP")

    nil
  end

  def jpeg?(bytes)
    bytes.length >= 4 && bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff && bytes[3] != 0xf7
  end

  def png?(bytes)
    starts_with?(bytes, PNG_SIGNATURE) && bytes.length >= 16 && read_uint32_be(bytes, PNG_SIGNATURE.length) == 13 && ascii_at?(bytes, 12, "IHDR")
  end

  def animated_png?(bytes)
    offset = PNG_SIGNATURE.length
    while offset + 8 <= bytes.length
      chunk_length = read_uint32_be(bytes, offset)
      chunk_type_offset = offset + 4
      return true if ascii_at?(bytes, chunk_type_offset, "acTL")
      return false if ascii_at?(bytes, chunk_type_offset, "IDAT")

      next_offset = offset + 8 + chunk_length + 4
      return false if next_offset <= offset || next_offset > bytes.length

      offset = next_offset
    end
    false
  end

  def read_uint32_be(bytes, offset)
    ((bytes[offset] || 0) << 24) + ((bytes[offset + 1] || 0) << 16) + ((bytes[offset + 2] || 0) << 8) + (bytes[offset + 3] || 0)
  end

  def starts_with?(bytes, prefix)
    return false if bytes.length < prefix.length

    prefix.each_with_index.all? { |byte, index| bytes[index] == byte }
  end

  def ascii_at?(bytes, offset, text)
    return false if bytes.length < offset + text.length

    text.bytes.each_with_index.all? { |byte, index| bytes[offset + index] == byte }
  end
end
