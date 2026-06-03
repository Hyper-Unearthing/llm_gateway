# frozen_string_literal: true

require "test_helper"
require "json"
require "tmpdir"
require "llm_gateway/agents/file_session_manager"

class FileSessionManagerTest < Test
  def with_tmpdir
    Dir.mktmpdir do |dir|
      yield dir
    end
  end

  def user_message(text)
    { role: "user", content: [ { type: "text", text: text } ] }
  end

  test "creates a JSONL session file and appends events" do
    with_tmpdir do |dir|
      session = LlmGateway::Agents::FileSessionManager.new(
        nil,
        session_id: "session-1",
        session_start: "20260521_120000",
        session_dir: dir
      )

      session.push_message(user_message("hello"))

      path = File.join(dir, "20260521_120000_session-1.jsonl")
      assert_equal path, session.session_path
      lines = File.readlines(path).map { |line| JSON.parse(line, symbolize_names: true) }

      assert_equal [ "session", "message" ], lines.map { |event| event[:type] }
      assert_equal "session-1", lines.first[:id]
      assert_equal user_message("hello"), lines.last[:data]
    end
  end

  test "loads an existing session and continues appending without persisting queued messages" do
    with_tmpdir do |dir|
      path = File.join(dir, "session.jsonl")
      original = LlmGateway::Agents::FileSessionManager.new(
        path,
        session_id: "session-1",
        session_start: "20260521_120000"
      )
      original.push_message(user_message("one"))

      loaded = LlmGateway::Agents::FileSessionManager.new(path)
      assert_equal "session-1", loaded.session_id
      assert_equal [ user_message("one") ], loaded.active_messages

      loaded.busy!
      loaded.push_message_to_queue(user_message("queued"))
      assert_equal 2, File.readlines(path).size

      loaded.idle!
      loaded.drain_message_queue(:next_turn, mode: :one_at_a_time)

      reloaded = LlmGateway::Agents::FileSessionManager.new(path)
      assert_equal [ user_message("one"), user_message("queued") ], reloaded.active_messages
      assert_equal 3, File.readlines(path).size
    end
  end

  test "raises a helpful error for invalid JSONL" do
    with_tmpdir do |dir|
      path = File.join(dir, "bad.jsonl")
      File.write(path, "{bad json\n")

      error = assert_raises(ArgumentError) do
        LlmGateway::Agents::FileSessionManager.new(path).events
      end

      assert_match(/Invalid JSONL in #{Regexp.escape(path)} at line 1:/, error.message)
    end
  end
end
