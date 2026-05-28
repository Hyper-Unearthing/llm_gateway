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
      { choices: [ { content: "ok" } ] }
    end
  end

  class ConfigurablePrompt < LlmGateway::Prompt
    def prompt
      "hello"
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

    ConfigurablePrompt.new.stream

    assert_equal "hello", provider.calls.last[:message]
    assert_equal "class-model", provider.calls.last[:options][:model]
  end

  test "initializer provider and model override class configuration" do
    class_provider = RecordingProvider.new
    instance_provider = RecordingProvider.new
    ConfigurablePrompt.provider = class_provider
    ConfigurablePrompt.model = "class-model"

    ConfigurablePrompt.new(instance_provider, "instance-model").stream

    assert_empty class_provider.calls
    assert_equal "instance-model", instance_provider.calls.last[:options][:model]
  end

  test "stream provider and model override instance configuration" do
    instance_provider = RecordingProvider.new
    stream_provider = RecordingProvider.new

    ConfigurablePrompt.new(instance_provider, "instance-model").stream(
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
    ).stream

    assert_equal "keyword-model", provider.calls.last[:options][:model]
    assert_equal "low", provider.calls.last[:options][:reasoning]
  end

  test "uses class reasoning and allows stream override" do
    provider = RecordingProvider.new
    ConfigurablePrompt.provider = provider
    ConfigurablePrompt.reasoning = "high"

    ConfigurablePrompt.new.stream(reasoning: "medium")

    assert_equal "medium", provider.calls.last[:options][:reasoning]
  end
end
