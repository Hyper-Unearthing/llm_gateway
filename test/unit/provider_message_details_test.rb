# frozen_string_literal: true

require "test_helper"

class ProviderMessageDetailsTest < Test
  DETAIL_MESSAGES = [
    { role: "user", content: "hello", details: { trace_id: "user-details" } },
    { role: "assistant", content: "hi", details: { trace_id: "assistant-details" } }
  ].freeze

  PROVIDER_API_PAIRS = [
    [ "openai completions", LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter, "openai/gpt-5.1", :stream ],
    [ "openai responses", LlmGateway::Adapters::OpenAI::ResponsesAdapter, "openai/gpt-5.4", :stream_responses ],
    [ "openai codex responses", LlmGateway::Adapters::OpenAICodex::ResponsesAdapter, "openai/gpt-5.4", :stream_codex ],
    [ "anthropic messages", LlmGateway::Adapters::Anthropic::MessagesAdapter, "anthropic/claude-sonnet-4-20250514", :stream ],
    [ "groq completions", LlmGateway::Adapters::Groq::ChatCompletionsAdapter, [ "groq", "openai/gpt-oss-120b" ], :stream ]
  ].freeze

  class CapturingClient
    attr_reader :captured_method, :captured_messages, :captured_tools, :captured_system, :captured_options

    def stream(messages, tools: nil, system: [], **options, &block)
      capture(:stream, messages, tools, system, options)
    end

    def stream_responses(messages, tools: nil, system: [], **options, &block)
      capture(:stream_responses, messages, tools, system, options)
    end

    def stream_codex(messages, tools: nil, system: [], **options, &block)
      capture(:stream_codex, messages, tools, system, options)
    end

    private

    def capture(method, messages, tools, system, options)
      @captured_method = method
      @captured_messages = messages
      @captured_tools = tools
      @captured_system = system
      @captured_options = options
      []
    end
  end

  PROVIDER_API_PAIRS.each do |name, adapter_class, model_reference, expected_method|
    test "#{name} excludes details from user and assistant messages" do
      client = CapturingClient.new
      adapter = adapter_class.new(client)

      model = model_reference.is_a?(Array) ? LlmGateway.models.fetch(provider: model_reference[0], id: model_reference[1]) : LlmGateway.models.fetch(model_reference)
      adapter.raw_stream(DETAIL_MESSAGES, model: model)

      assert_equal expected_method, client.captured_method
      assert_no_message_details client.captured_messages
    end
  end

  private

  def assert_no_message_details(messages)
    refute_empty messages
    messages.each do |message|
      next unless message.is_a?(Hash)

      refute message.key?(:details), "expected details to be excluded from #{message.inspect}"
      refute message.key?("details"), "expected details to be excluded from #{message.inspect}"
    end
  end
end
