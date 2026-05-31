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

    def execute(input)
      input[:left] + input[:right]
    end
  end

  class ToolPrompt < ConfigurablePrompt
    TOOLS = [ AddTool ].freeze
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
    ConfigurablePrompt.provider = nil
    ConfigurablePrompt.model = nil
    ConfigurablePrompt.reasoning = nil
  end

  test "uses provider and model configured on the class" do
    provider = RecordingProvider.new
    ConfigurablePrompt.provider = provider
    ConfigurablePrompt.model = "class-model"

    prompt = ConfigurablePrompt.new
    prompt.run

    assert_equal provider, prompt.provider
    assert_equal "class-model", prompt.model
    assert_equal "hello", provider.calls.last[:message]
    assert_equal "class-model", provider.calls.last[:options][:model]
  end

  test "initializer provider and model keywords override class configuration" do
    class_provider = RecordingProvider.new
    instance_provider = RecordingProvider.new
    ConfigurablePrompt.provider = class_provider
    ConfigurablePrompt.model = "class-model"

    ConfigurablePrompt.new(provider: instance_provider, model: "instance-model").run

    assert_empty class_provider.calls
    assert_equal "instance-model", instance_provider.calls.last[:options][:model]
  end

  test "run provider and model override instance configuration" do
    instance_provider = RecordingProvider.new
    stream_provider = RecordingProvider.new

    ConfigurablePrompt.new(provider: instance_provider, model: "instance-model").run(
      provider: stream_provider,
      model: "stream-model"
    )

    assert_empty instance_provider.calls
    assert_equal "stream-model", stream_provider.calls.last[:options][:model]
  end

  test "accepts provider model and reasoning as initializer keywords" do
    provider = RecordingProvider.new

    ConfigurablePrompt.new(
      provider: provider,
      model: "keyword-model",
      reasoning: "low"
    ).run

    assert_equal "keyword-model", provider.calls.last[:options][:model]
    assert_equal "low", provider.calls.last[:options][:reasoning]
  end

  test "uses class reasoning and allows run override" do
    provider = RecordingProvider.new
    ConfigurablePrompt.provider = provider
    ConfigurablePrompt.reasoning = "high"

    ConfigurablePrompt.new.run(reasoning: "medium")

    assert_equal "medium", provider.calls.last[:options][:reasoning]
  end

  test "run executes tool calls and continues with tool results" do
    provider = SequentialProvider.new(
      assistant_message(content: [ { type: "tool_use", id: "toolu_add", name: "add", input: { left: 2, right: 3 } } ], stop_reason: "tool_use"),
      assistant_message(content: [ { type: "text", text: "5" } ])
    )

    result = ToolPrompt.new(provider: provider, model: "test-model").run

    assert_equal "5", result
    assert_equal 2, provider.calls.length
    assert_equal [ AddTool.definition ], provider.calls.first[:options][:tools]
    assert_equal "hello", provider.calls.first[:message]
    continued_message = provider.calls[1][:message]
    assert_equal "user", continued_message[0][:role]
    assert_equal "hello", continued_message[0][:content]
    assert_equal "assistant", continued_message[1][:role]
    assert_equal [ { type: "tool_result", tool_use_id: "toolu_add", content: 5 } ], continued_message[2][:content]
    assert_equal "test-model", provider.calls[1][:options][:model]
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
