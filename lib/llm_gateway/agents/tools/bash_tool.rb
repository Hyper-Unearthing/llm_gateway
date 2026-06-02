require "securerandom"
require "tmpdir"
require_relative "tool_utils"

class BashTool < LlmGateway::Tool
  # Pi adaptation notes:
  # - Keep timeout schema as integer: gruv treats integer and number schemas equivalently for seconds.
  # - Do not add pi's pluggable operations, shell/env hooks, command prefix, AbortSignal handling, partial updates, or UI render details: those are runtime/UI extension concerns outside this tool contract.
  name "bash"
  description "Execute a bash command in the current working directory. Returns stdout and stderr. Output is truncated to last #{ToolUtils::DEFAULT_MAX_LINES} lines or #{ToolUtils::DEFAULT_MAX_BYTES / 1024}KB (whichever is hit first). If truncated, full output is saved to a temp file. Optionally provide a timeout in seconds."
  input_schema({
    type: "object",
    properties: {
      command: { type: "string", description: "Bash command to execute" },
      timeout: { type: "integer", description: "Timeout in seconds (optional, no default timeout)" }
    },
    required: [ "command" ]
  })

  def execute(input)
    command = input[:command]
    timeout = input[:timeout]

    result = run_command(command, timeout)
    out = format_output(result[:output], empty_text: result[:timed_out] ? "" : "(no output)")

    if result[:timed_out]
      return append_status(out, "Command timed out after #{timeout} seconds")
    end

    if result[:exit_status] && result[:exit_status] != 0
      return append_status(out, "Command exited with code #{result[:exit_status]}")
    end

    out
  rescue StandardError => e
    e.message
  end

  private

  def run_command(command, timeout)
    output = +""
    timed_out = false
    read_io, write_io = IO.pipe
    pid = Process.spawn(command, chdir: Dir.pwd, in: File::NULL, out: write_io, err: write_io, pgroup: true)
    write_io.close

    deadline = timeout && timeout.positive? ? Time.now + timeout : nil

    loop do
      remaining = deadline ? deadline - Time.now : nil
      if remaining && remaining <= 0
        timed_out = true
        terminate_process_group(pid)
        break
      end

      ready = IO.select([ read_io ], nil, nil, remaining)
      unless ready
        timed_out = true
        terminate_process_group(pid)
        break
      end

      begin
        output << read_io.readpartial(16 * 1024)
      rescue EOFError
        break
      end
    end

    _, status = Process.wait2(pid)
    drain_available_output(read_io, output)
    read_io.close

    { output: output, exit_status: status.exitstatus, timed_out: timed_out }
  ensure
    write_io.close if write_io && !write_io.closed?
    read_io.close if read_io && !read_io.closed?
  end

  def drain_available_output(read_io, output)
    loop do
      ready = IO.select([ read_io ], nil, nil, 0.1)
      break unless ready

      begin
        output << read_io.readpartial(16 * 1024)
      rescue EOFError
        break
      end
    end
  end

  def terminate_process_group(pid)
    Process.kill("TERM", -pid)
    sleep 0.1
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def format_output(output, empty_text: "(no output)")
    truncation = ToolUtils.truncate_tail(output)
    out = truncation[:content]
    out = empty_text if out.empty?

    return out unless truncation[:truncated]

    temp_path = File.join(Dir.tmpdir, "pi-bash-#{SecureRandom.hex(8)}.log")
    File.write(temp_path, output)

    start_line = truncation[:total_lines] - truncation[:output_lines] + 1
    end_line = truncation[:total_lines]

    notice = if truncation[:last_line_partial]
      last_line = output.split("\n", -1).last
      "[Showing last #{ToolUtils.format_size(truncation[:output_bytes])} of line #{end_line} (line is #{ToolUtils.format_size(last_line.bytesize)}). Full output: #{temp_path}]"
    elsif truncation[:truncated_by] == "lines"
      "[Showing lines #{start_line}-#{end_line} of #{truncation[:total_lines]}. Full output: #{temp_path}]"
    else
      "[Showing lines #{start_line}-#{end_line} of #{truncation[:total_lines]} (#{ToolUtils.format_size(ToolUtils::DEFAULT_MAX_BYTES)} limit). Full output: #{temp_path}]"
    end

    "#{out}\n\n#{notice}"
  end

  def append_status(text, status)
    text.empty? ? status : "#{text}\n\n#{status}"
  end
end
