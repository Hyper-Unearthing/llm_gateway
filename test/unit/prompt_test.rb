# frozen_string_literal: true

require_relative "../test_helper"

class PromptTest < Test
  class RecordingProvider
    attr_reader :calls

    def initialize
      @calls = []
    end

    def stream(message, **options)
      @calls << { message: message, options: options }
      AssistantMessage.new(
        id: "msg_recording",
        model: options[:model] || "test-model",
        usage: {},
        role: "assistant",
        stop_reason: "stop",
        provider: "test",
        api: "test",
        timestamp: Time.now.to_i,
        content: [ { type: "text", text: "ok" } ]
      )
    end
  end

  class ConfigurablePrompt < LlmGateway::Prompt
    def prompt
      "hello"
    end
  end

  class AddTool < LlmGateway::Tool
    name "add"
    description "Adds two numbers"
    input_schema({ type: "object" })

    def execute(input, tool_use_id:)
      tool_result(input[:left] + input[:right], tool_use_id: tool_use_id)
    end
  end

  class ToolPrompt < ConfigurablePrompt
    TOOLS = [ AddTool ].freeze
  end

  class CustomToolResultMessagePrompt < ToolPrompt
    TOOLS = ToolPrompt::TOOLS

    def execute_tool_requests(requests:, assistant_message:, session_event:)
      tool_results = yield requests
      LlmGateway::Agents::Event::ToolResultMessage.new(
        role: "developer",
        content: tool_results,
        details: {
          assistant_message_id: assistant_message.id,
          request_count: requests.length
        }
      )
    end
  end

  class AroundToolExecutionPrompt < ToolPrompt
    TOOLS = ToolPrompt::TOOLS

    def execute_tool_requests(requests:, assistant_message:, session_event:)
      context = { assistant_message_id: assistant_message.id, request_names: requests.map(&:name), session_event: session_event }

      tool_results = yield(requests).map do |result|
        LlmGateway::Agents::Event::ToolCallResult.new(
          tool_use_id: result.tool_use_id,
          content: { context: context, result: result.content },
          is_error: result.is_error
        )
      end

      LlmGateway::Agents::Event::ToolResultMessage.new(content: tool_results)
    end
  end

  class SequentialProvider
    attr_reader :calls

    def initialize(*responses)
      @responses = responses
      @calls = []
    end

    def stream(message, **options)
      @calls << { message: message, options: options }
      @responses.shift
    end
  end

  def setup
    ConfigurablePrompt.adapter = nil
    ConfigurablePrompt.model = nil
    ConfigurablePrompt.reasoning = nil
  end

  test "uses adapter and model configured on the class" do
    provider = RecordingProvider.new
    ConfigurablePrompt.adapter = provider
    ConfigurablePrompt.model = "class-model"

    prompt = ConfigurablePrompt.new
    prompt.run

    assert_equal provider, prompt.adapter
    assert_equal "class-model", prompt.model
    assert_equal "hello", provider.calls.last[:message]
    assert_equal "class-model", provider.calls.last[:options][:model]
  end

  test "initializer adapter and model keywords override class configuration" do
    class_provider = RecordingProvider.new
    instance_provider = RecordingProvider.new
    ConfigurablePrompt.adapter = class_provider
    ConfigurablePrompt.model = "class-model"

    ConfigurablePrompt.new(adapter: instance_provider, model: "instance-model").run

    assert_empty class_provider.calls
    assert_equal "instance-model", instance_provider.calls.last[:options][:model]
  end

  test "run adapter and model override instance configuration" do
    instance_provider = RecordingProvider.new
    stream_provider = RecordingProvider.new

    ConfigurablePrompt.new(adapter: instance_provider, model: "instance-model").run(
      adapter: stream_provider,
      model: "stream-model"
    )

    assert_empty instance_provider.calls
    assert_equal "stream-model", stream_provider.calls.last[:options][:model]
  end

  test "accepts adapter model and reasoning as initializer keywords" do
    provider = RecordingProvider.new

    ConfigurablePrompt.new(
      adapter: provider,
      model: "keyword-model",
      reasoning: "low"
    ).run

    assert_equal "keyword-model", provider.calls.last[:options][:model]
    assert_equal "low", provider.calls.last[:options][:reasoning]
  end

  test "uses class reasoning and allows run override" do
    provider = RecordingProvider.new
    ConfigurablePrompt.adapter = provider
    ConfigurablePrompt.reasoning = "high"

    ConfigurablePrompt.new.run(reasoning: "medium")

    assert_equal "medium", provider.calls.last[:options][:reasoning]
  end

  test "run executes tool calls and continues with tool results" do
    provider = SequentialProvider.new(
      assistant_message(content: [ { type: "tool_use", id: "toolu_add", name: "add", input: { left: 2, right: 3 } } ], stop_reason: "tool_use"),
      assistant_message(content: [ { type: "text", text: "5" } ])
    )

    result = ToolPrompt.new(adapter: provider, model: "test-model").run

    assert_equal [ "5" ], result.content.map(&:text)
    assert_equal 2, provider.calls.length
    assert_equal [ AddTool.definition ], provider.calls.first[:options][:tools]
    assert_equal "hello", provider.calls.first[:message]
    continued_message = provider.calls[1][:message]
    assert_equal "user", continued_message[0][:role]
    assert_equal "hello", continued_message[0][:content]
    assert_equal "assistant", continued_message[1][:role]
    assert_equal [ { type: "tool_result", tool_use_id: "toolu_add", content: 5, is_error: false } ], continued_message[2][:content]
    assert_equal "test-model", provider.calls[1][:options][:model]
  end

  test "allows prompts to customize the tool result wrapper message" do
    provider = SequentialProvider.new(
      assistant_message(content: [ { type: "tool_use", id: "toolu_add", name: "add", input: { left: 2, right: 3 } } ], stop_reason: "tool_use"),
      assistant_message(content: [ { type: "text", text: "5" } ])
    )

    CustomToolResultMessagePrompt.new(adapter: provider, model: "test-model").run

    continued_message = provider.calls[1][:message]
    assert_equal "developer", continued_message[2][:role]
    assert_equal [ { type: "tool_result", tool_use_id: "toolu_add", content: 5, is_error: false } ], continued_message[2][:content]
    assert_equal({ assistant_message_id: continued_message[1][:id], request_count: 1 }, continued_message[2][:details])
  end

  test "allows prompts to wrap tool execution" do
    provider = SequentialProvider.new(
      assistant_message(content: [ { type: "tool_use", id: "toolu_add", name: "add", input: { left: 2, right: 3 } } ], stop_reason: "tool_use"),
      assistant_message(content: [ { type: "text", text: "5" } ])
    )

    AroundToolExecutionPrompt.new(adapter: provider, model: "test-model").run

    continued_message = provider.calls[1][:message]
    expected_content = {
      context: {
        assistant_message_id: continued_message[1][:id],
        request_names: [ "add" ],
        session_event: nil
      },
      result: 5
    }
    assert_equal [ { type: "tool_result", tool_use_id: "toolu_add", content: expected_content, is_error: false } ],
      continued_message[2][:content]
  end

  private

  def assistant_message(content:, stop_reason: "stop")
    AssistantMessage.new(
      id: "msg_#{object_id}_#{rand(1000)}",
      model: "test-model",
      usage: {},
      role: "assistant",
      stop_reason: stop_reason,
      provider: "test",
      api: "test",
      timestamp: Time.now.to_i,
      content: content
    )
  end
end
