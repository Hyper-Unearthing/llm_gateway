# frozen_string_literal: true

require "test_helper"

class ConfigureTest < Test
  def teardown
    LlmGateway.reset_configuration!
  end

  test "configures clients accessible as static methods" do
    LlmGateway.configure([
      {
        name: "anthropic_sonnet",
        config: {
          provider: "anthropic_apikey_messages",
          api_key: "sk-ant-test-key"
        }
      },
      {
        name: "groq",
        config: {
          provider: "groq_apikey_completions",
          api_key: "gsk-test-key"
        }
      }
    ])

    assert_respond_to LlmGateway, :anthropic_sonnet
    assert_respond_to LlmGateway, :groq
    assert_instance_of LlmGateway::Adapters::Claude::MessagesAdapter, LlmGateway.anthropic_sonnet
    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, LlmGateway.groq
  end

  test "stores clients in configured_clients hash" do
    LlmGateway.configure([
      {
        name: "my_openai",
        config: {
          provider: "openai_apikey_completions",
          api_key: "sk-openai-test-key"
        }
      }
    ])

    assert_equal 1, LlmGateway.configured_clients.size
    assert LlmGateway.configured_clients.key?(:my_openai)
  end

  test "raises error when name is missing" do
    assert_raises(ArgumentError) do
      LlmGateway.configure([
        { config: { provider: "groq_apikey_completions", api_key: "gsk-test-key" } }
      ])
    end
  end

  test "reset_configuration removes dynamic methods" do
    LlmGateway.configure([
      {
        name: "temp_client",
        config: {
          provider: "groq_apikey_completions",
          api_key: "gsk-test-key"
        }
      }
    ])

    assert_respond_to LlmGateway, :temp_client

    LlmGateway.reset_configuration!

    refute_respond_to LlmGateway, :temp_client
    assert_empty LlmGateway.configured_clients
  end

  test "works with string keys" do
    LlmGateway.configure([
      {
        "name" => "string_key_client",
        "config" => {
          "provider" => "groq_apikey_completions",
          "api_key" => "gsk-test-key"
        }
      }
    ])

    assert_respond_to LlmGateway, :string_key_client
    assert_instance_of LlmGateway::Adapters::Groq::ChatCompletionsAdapter, LlmGateway.string_key_client
  end
end
