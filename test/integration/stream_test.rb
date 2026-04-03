# frozen_string_literal: true

require "test_helper"
require "vcr"
require "json"
require "base64"
require "time"
require "fileutils"
require_relative "../utils/calculator_tool_helper"

class ProvidersJsonTest < Test
  include CalculatorToolHelper
  def teardown
    LlmGateway.reset_configuration!
  end

  def load_provider(provider:, model:)
    config = {
      "provider" => provider,
      "model_key" => model
    }

    case provider
    when "openai_apikey_completions", "openai_apikey_responses"
      api_key = ENV["OPENAI_API_KEY"].to_s
      skip("Skipped: missing OPENAI_API_KEY") if api_key.empty?
      config["api_key"] = api_key
    when "anthropic_apikey_messages"
      api_key = ENV["ANTHROPIC_API_KEY"].to_s
      skip("Skipped: missing ANTHROPIC_API_KEY") if api_key.empty?
      config["api_key"] = api_key
    when "anthropic_oauth_messages"
      config["provider"] = "anthropic_apikey_messages"
      config["api_key"] = oauth_access_token_for("anthropic")
    when "openai_oauth_codex"
      creds = load_auth_credentials("openai")
      config["api_key"] = oauth_access_token_for("openai")
      config["account_id"] = creds["account_id"] if creds["account_id"]
    end

    LlmGateway.build_provider(config)
  end

  def skip_on_authentication_error
    yield
  rescue LlmGateway::Errors::AuthenticationError,
         LlmGateway::Errors::BadRequestError,
         LlmGateway::Errors::RateLimitError,
         LlmGateway::Errors::APIStatusError => e
    skip("Skipped due to provider error: #{e.message}")
  end

  def auth_file_path
    File.expand_path(ENV.fetch("LLM_GATEWAY_AUTH_FILE", "~/.config/llm_gateway/auth.json"))
  end

  def load_auth_credentials(provider)
    path = auth_file_path
    skip("Skipped: missing auth file at #{path}") unless File.exist?(path)

    auth = JSON.parse(File.read(path))
    creds = auth[provider]
    skip("Skipped: missing #{provider} credentials in #{path}") unless creds

    creds
  end

  def persist_auth_credentials(provider, attributes)
    path = auth_file_path
    FileUtils.mkdir_p(File.dirname(path))

    auth = File.exist?(path) ? JSON.parse(File.read(path)) : {}
    auth[provider] ||= {}
    auth[provider].merge!(attributes)

    File.write(path, JSON.pretty_generate(auth) + "\n")
  end

  def oauth_access_token_for(provider)
    creds = load_auth_credentials(provider)

    case provider
    when "anthropic"
      token = LlmGateway::Clients::Claude.new.get_oauth_access_token(
        access_token: creds["access_token"],
        refresh_token: creds["refresh_token"],
        expires_at: creds["expires_at"]
      ) do |access_token, refresh_token, expires_at|
        persist_auth_credentials("anthropic", {
          "access_token" => access_token,
          "refresh_token" => refresh_token,
          "expires_at" => expires_at&.iso8601
        })
      end

      persist_auth_credentials("anthropic", { "access_token" => token }) if token != creds["access_token"]
      token
    when "openai"
      token = LlmGateway::Clients::OpenAi.new.get_oauth_access_token(
        access_token: creds["access_token"],
        refresh_token: creds["refresh_token"],
        expires_at: creds["expires_at"],
        account_id: creds["account_id"]
      ) do |access_token, refresh_token, expires_at|
        persist_auth_credentials("openai", {
          "access_token" => access_token,
          "refresh_token" => refresh_token,
          "expires_at" => expires_at&.iso8601
        })
      end

      persist_auth_credentials("openai", { "access_token" => token }) if token != creds["access_token"]
      token
    else
      raise ArgumentError, "Unsupported OAuth provider: #{provider}"
    end
  end

  def assert_basic_text_generation_result(message, expected_text)
    assert_equal "assistant", message.role
    assert_operator message.usage[:input_tokens], :>, 0
    assert_operator message.usage[:output_tokens], :>, 0
    assert_nil message.error_message
    response_text = message.content
      .select { |block| block.type == "text" }
      .map(&:text)
      .join
    assert_includes response_text, expected_text
  end

  def basic_text_generation_test(adapter)
    first_prompt = "Reply with exactly: 'Hello test successful'"
    first_response = adapter.stream(first_prompt)

    assert_basic_text_generation_result(first_response, "Hello test successful")

    second_prompt = "Now say 'Goodbye test successful'"
    transcript = [
      { role: "user", content: first_prompt },
      first_response.to_h,
      { role: "user", content: second_prompt }
    ]
    second_response = adapter.stream(transcript)

    assert_basic_text_generation_result(second_response, "Goodbye test successful")
  end

  def basic_tool_call(adapter)
    prompt = "Calculate 15 + 27 using the math_operation tool"
    accumulated_tool_args = ""
    has_tool_start = false
    has_tool_delta = false
    has_tool_end = false
    response = adapter.stream(prompt, tools: [ math_operation_tool ]) do |event|
      if event.type == :tool_start
        has_tool_start = true
        assert_equal "math_operation", event.name
      end
      if event.type == :tool_delta
        has_tool_delta = true
        accumulated_tool_args += event.delta
      end
      if event.type == :tool_end
        has_tool_end = true
        parsed_args = JSON.parse(accumulated_tool_args)
        assert_equal(15, parsed_args["a"])
        assert_equal(27, parsed_args["b"])
        assert_equal("add", parsed_args["operation"])
      end
    end

    assert_equal true, has_tool_start, "tool start event occured"
    assert_equal true, has_tool_delta, "tool delta event occured"
    assert_equal true, has_tool_end, "tool end event occured"

    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message
    assert_includes [ "tool_use" ], response.stop_reason

    tool_call = response.content.find { |block| block.type == "tool_use" }
    refute_nil tool_call
    assert_equal "math_operation", tool_call.name
    assert tool_call.id
    refute_nil tool_call.input
    assert_equal 15, tool_call.input[:a]
    assert_equal 27, tool_call.input[:b]
    assert_includes %w[add subtract multiply divide], tool_call.input[:operation]
  end

  def basic_thinking_test(adapter, reasoning: "high")
    prompt = "Think long and hard about #{rand(100_000)} + 27"
    thinking_started = false
    thinking_chunks = ""
    thinking_completed = false
    response = adapter.stream(prompt, reasoning:,) do |event|
      case event.type
      when :reasoning_start
        thinking_started = true
        thinking_chunks += event.delta
      when :reasoning_delta
        thinking_chunks += event.delta
      when :reasoning_end
        thinking_completed = true
      end
    end

    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message
    assert_equal "stop", response.stop_reason, "Error: #{response.error_message}"

    if thinking_started || thinking_completed || !thinking_chunks.empty?
      assert_equal true, thinking_started, "thinking start event occurred"
      assert_operator thinking_chunks.length, :>, 0
      assert_equal true, thinking_completed, "thinking end event occurred"

      thinking_block = response.content.find { |block| block.type == "reasoning" }
      refute_nil thinking_block
      refute_empty thinking_block.reasoning.to_s
    else
      assert_operator response.usage[:reasoning_tokens], :>, 0
    end
  end

  def basic_streaming_text_test(adapter)
    text_started = false
    text_chunks = ""
    text_completed = false

    response = adapter.stream("Count from 1 to 3") do |event|
      case event.type
      when :text_start
        text_started = true
        text_chunks += event.delta
      when :text_delta
        text_chunks += event.delta
      when :text_end
        text_completed = true
      end
    end

    assert_equal true, text_started, "text start event occurred"
    assert_operator text_chunks.length, :>, 0
    assert_equal true, text_completed, "text end event occurred"
    assert_equal "assistant", response.role
    assert response.content.any? { |block| block.type == "text" }
  end

  def multi_turn_tool_stream_test(adapter, reasoning: "high")
    transcript = [
      {
        role: "user",
        content: "Think about this briefly, then calculate 42 * 17 and 453 + 434 using the math_operation tool."
      }
    ]

    all_text_content = +""
    has_seen_thinking = false
    has_seen_tool_calls = false
    max_turns = 5

    max_turns.times do
      streamed_tool_args = Hash.new { |hash, key| hash[key] = +"" }

      stream_kwargs = {
        tools: [ math_operation_tool ],
        system: "You are a helpful assistant that can use tools to answer questions."
      }
      stream_kwargs[:reasoning] = reasoning if reasoning

      response = adapter.stream(
        transcript,
        **stream_kwargs
      ) do |event|
        case event.type
        when :reasoning_start, :reasoning_delta, :reasoning_end
          has_seen_thinking = true
        when :tool_start
          has_seen_tool_calls = true
          assert_equal "math_operation", event.name
          assert event.id
        when :tool_delta
          has_seen_tool_calls = true
          streamed_tool_args[event.content_index] += event.delta
        when :tool_end
          has_seen_tool_calls = true
        end
      end

      transcript << response.to_h

      results = []
      response.content.each_with_index do |block, index|
        case block.type
        when "text"
          all_text_content += block.text
        when "reasoning"
          has_seen_thinking = true
        when "tool_use"
          has_seen_tool_calls = true

          assert_equal "math_operation", block.name
          assert block.id
          refute_nil block.input
          refute_empty streamed_tool_args[index] unless streamed_tool_args[index].empty?

          result = evaluate_math_operation(block.input)

          results << {
            role: "developer",
            content: [
              {
                type: "tool_result",
                tool_use_id: block.id,
                content: result.to_s
              }
            ]
          }
        end
      end

      transcript.concat(results)

      refute_equal "error", response.stop_reason, "Error: #{response.error_message}"
      break if response.stop_reason == "stop"
    end

    assert_equal true, (has_seen_thinking || has_seen_tool_calls)

    if all_text_content.empty?
      assert_equal true, has_seen_tool_calls
    else
      assert_includes all_text_content, "714"
      assert_includes all_text_content, "887"
    end
  end

  def basic_image_streaming_test(adapter)
    image_path = File.expand_path("../fixtures/red-circle.png", __dir__)
    image_data = Base64.strict_encode64(File.binread(image_path))

    prompt = [
      {
        role: "user",
        content: [
          {
            type: "text",
            text: "What do you see in this image? Please describe the shape (circle, rectangle, square, triangle, ...) and color (red, blue, green, ...). You MUST reply in English."
          },
          {
            type: "image",
            data: image_data,
            media_type: "image/png"
          }
        ]
      }
    ]

    response = adapter.stream(prompt, system: "You are a helpful assistant.")

    assert_equal "assistant", response.role
    assert_operator response.usage[:input_tokens], :>, 0
    assert_operator response.usage[:output_tokens], :>, 0
    assert_nil response.error_message

    text_content = response.content.find { |block| block.type == "text" }
    refute_nil text_content

    lower_content = text_content.text.downcase
    assert_includes lower_content, "red"
    assert_includes lower_content, "circle"
  end
  def self.define_stream_tests_for(name:, provider:, model:)
    test "#{name} basic text generation" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          basic_text_generation_test(adapter)
        end
      end
    end

    test "#{name} basic tool call" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          basic_tool_call(adapter)
        end
      end
    end

    test "#{name} basic thinking" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          basic_thinking_test(adapter, reasoning: "high")
        end
      end
    end

    test "#{name} text streaming" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          basic_streaming_text_test(adapter)
        end
      end
    end

    test "#{name} multi turn tool streaming" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          multi_turn_tool_stream_test(adapter, reasoning: "high")
        end
      end
    end

    test "#{name} image streaming" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          basic_image_streaming_test(adapter)
        end
      end
    end
  end

  define_stream_tests_for(
    name: "openai_apikey_completions_gpt_5_1",
    provider: "openai_apikey_completions",
    model: "gpt-5.1"
  )

  define_stream_tests_for(
    name: "anthropic_apikey_messages_claude_sonnet_4",
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_tests_for(
    name: "openai_apikey_responses_gpt_5_4",
    provider: "openai_apikey_responses",
    model: "gpt-5.4"
  )

  define_stream_tests_for(
    name: "anthropic_oauth_messages_claude_sonnet_4",
    provider: "anthropic_oauth_messages",
    model: "claude-sonnet-4-20250514"
  )

  define_stream_tests_for(
    name: "openai_oauth_codex_gpt_5_4",
    provider: "openai_oauth_codex",
    model: "gpt-5.4"
  )
end
