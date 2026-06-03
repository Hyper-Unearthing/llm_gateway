require "pathname"
require "thread"

module ToolUtils
  DEFAULT_MAX_LINES = 2000
  DEFAULT_MAX_BYTES = 50 * 1024

  @file_mutation_locks = Hash.new { |hash, key| hash[key] = Mutex.new }
  @file_mutation_locks_mutex = Mutex.new

  module_function

  def with_file_mutation_lock(path)
    lock = @file_mutation_locks_mutex.synchronize { @file_mutation_locks[path] }
    lock.synchronize { yield }
  end

  def format_size(bytes)
    return "#{bytes}B" if bytes < 1024
    return format("%.1fKB", bytes / 1024.0) if bytes < 1024 * 1024

    format("%.1fMB", bytes / (1024.0 * 1024.0))
  end

  def expand_path(file_path)
    normalized = file_path.to_s.sub(/^@/, "").gsub(/[\u00A0\u2000-\u200A\u202F\u205F\u3000]/, " ")
    return Dir.home if normalized == "~"
    return File.join(Dir.home, normalized[2..]) if normalized.start_with?("~/")

    normalized
  end

  def resolve_to_cwd(file_path, cwd = Dir.pwd)
    expanded = expand_path(file_path)
    Pathname.new(expanded).absolute? ? expanded : File.expand_path(expanded, cwd)
  end

  def resolve_read_path(file_path, cwd = Dir.pwd)
    resolved = resolve_to_cwd(file_path, cwd)
    return resolved if File.exist?(resolved)

    am_pm_variant = resolved.gsub(/ (AM|PM)\./i) { "\u202F#{Regexp.last_match(1)}." }
    return am_pm_variant if File.exist?(am_pm_variant)

    nfd_variant = resolved.unicode_normalize(:nfd)
    return nfd_variant if File.exist?(nfd_variant)

    curly_variant = resolved.tr("'", "\u2019")
    return curly_variant if File.exist?(curly_variant)

    nfd_curly_variant = nfd_variant.tr("'", "\u2019")
    return nfd_curly_variant if File.exist?(nfd_curly_variant)

    resolved
  end

  def truncate_head(content, max_lines: DEFAULT_MAX_LINES, max_bytes: DEFAULT_MAX_BYTES)
    lines = split_lines_for_counting(content)
    total_lines = lines.length
    total_bytes = content.bytesize

    if total_lines <= max_lines && total_bytes <= max_bytes
      return truncation_result(content, false, nil, total_lines, total_bytes, total_lines, total_bytes, false, false, max_lines, max_bytes)
    end

    first_line_bytes = lines.first.to_s.bytesize
    if first_line_bytes > max_bytes
      return truncation_result("", true, "bytes", total_lines, total_bytes, 0, 0, false, true, max_lines, max_bytes)
    end

    out_lines = []
    out_bytes = 0
    truncated_by = "lines"

    lines.each_with_index do |line, index|
      break if index >= max_lines

      line_bytes = line.bytesize + (index.positive? ? 1 : 0)
      if out_bytes + line_bytes > max_bytes
        truncated_by = "bytes"
        break
      end

      out_lines << line
      out_bytes += line_bytes
    end

    output = out_lines.join("\n")
    truncation_result(output, true, truncated_by, total_lines, total_bytes, out_lines.length, output.bytesize, false, false, max_lines, max_bytes)
  end

  def truncate_tail(content, max_lines: DEFAULT_MAX_LINES, max_bytes: DEFAULT_MAX_BYTES)
    lines = split_lines_for_counting(content)
    total_lines = lines.length
    total_bytes = content.bytesize

    if total_lines <= max_lines && total_bytes <= max_bytes
      return truncation_result(content, false, nil, total_lines, total_bytes, total_lines, total_bytes, false, false, max_lines, max_bytes)
    end

    out_lines = []
    out_bytes = 0
    truncated_by = "lines"
    last_line_partial = false

    (lines.length - 1).downto(0) do |i|
      break if out_lines.length >= max_lines

      line = lines[i]
      line_bytes = line.bytesize + (out_lines.empty? ? 0 : 1)

      if out_bytes + line_bytes > max_bytes
        truncated_by = "bytes"
        if out_lines.empty?
          out_lines.unshift(truncate_string_to_bytes_from_end(line, max_bytes))
          out_bytes = out_lines.first.bytesize
          last_line_partial = true
        end
        break
      end

      out_lines.unshift(line)
      out_bytes += line_bytes
    end

    output = out_lines.join("\n")
    truncation_result(output, true, truncated_by, total_lines, total_bytes, out_lines.length, output.bytesize, last_line_partial, false, max_lines, max_bytes)
  end

  def split_lines_for_counting(content)
    return [] if content.empty?

    lines = content.split("\n", -1)
    lines.pop if content.end_with?("\n")
    lines
  end

  def truncation_result(content, truncated, truncated_by, total_lines, total_bytes, output_lines, output_bytes, last_line_partial, first_line_exceeds_limit, max_lines, max_bytes)
    {
      content: content,
      truncated: truncated,
      truncated_by: truncated_by,
      total_lines: total_lines,
      total_bytes: total_bytes,
      output_lines: output_lines,
      output_bytes: output_bytes,
      last_line_partial: last_line_partial,
      first_line_exceeds_limit: first_line_exceeds_limit,
      max_lines: max_lines,
      max_bytes: max_bytes
    }
  end

  def truncate_string_to_bytes_from_end(str, max_bytes)
    bytes = str.dup.force_encoding("UTF-8").bytes
    return str if bytes.length <= max_bytes

    tail = bytes.last(max_bytes).pack("C*")
    until tail.valid_encoding?
      tail = tail.bytes.drop(1).pack("C*")
    end
    tail
  end
end
