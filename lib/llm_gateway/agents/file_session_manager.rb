# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "in_memory_session_manager"

module LlmGateway
  module Agents
    class FileSessionManager < InMemorySessionManager
      attr_reader :file_name, :session_path

      def initialize(file_name = nil, session_id: nil, session_start: nil, session_dir: nil)
        super(session_id)
        @file_name = file_name
        @preset_session_start = session_start
        @session_dir = session_dir
      end

      def session_id
        events
        @session_id
      end

      def session_start
        events
        @session_start
      end

      def normalize_path(file_name)
        File.expand_path(file_name)
      end

      def events
        @events ||= begin
          @session_path = normalize_path(file_name) if file_name
          if @session_path && File.exist?(@session_path)
            load_session(@session_path)
          else
            create_new_session
          end
        end
      end

      private

      def create_new_session
        @session_id ||= SecureRandom.uuid
        @session_start = @preset_session_start || Time.now.strftime("%Y%m%d_%H%M%S")

        session_event = {
          type: "session",
          id: @session_id,
          timestamp: @session_start
        }

        @session_path ||= File.join(session_dir, "#{@session_start}_#{@session_id}.jsonl")
        FileUtils.mkdir_p(File.dirname(@session_path))
        File.open(@session_path, "a") do |file|
          file.puts(JSON.generate(session_event))
        end

        [ session_event ]
      end

      def load_session(path)
        loaded_events = []
        File.foreach(path).with_index(1) do |line, line_number|
          next if line.strip.empty?

          loaded_events << JSON.parse(line, symbolize_names: true)
        rescue JSON::ParserError => e
          raise ArgumentError, "Invalid JSONL in #{path} at line #{line_number}: #{e.message}"
        end

        session_event = loaded_events.find { |event| event[:type] == "session" }
        @session_id = session_event[:id] if session_event&.dig(:id)
        @session_start = session_event[:timestamp] if session_event&.dig(:timestamp)

        loaded_events
      end

      def persist_entry(entry)
        attributes = super

        FileUtils.mkdir_p(File.dirname(session_path))
        File.open(session_path, "a") do |file|
          file.puts(JSON.generate(entry))
        end

        attributes
      end

      def session_dir
        File.expand_path(@session_dir || ENV.fetch("LLM_GATEWAY_SESSION_DIR", "~/.llm_gateway/sessions"))
      end
    end
  end
end
