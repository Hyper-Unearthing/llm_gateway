# frozen_string_literal: true

require "test_helper"
require "net/http"
require "uri"
require_relative "../utils/live_test_helper"

class CacheLiveTest < Test
  include LiveTestHelper

  DOCUMENT_URL = "https://gist.githubusercontent.com/billybonks/f343b02cc67535475b8819d281763c21/raw/c55972e604ecc9b5b998ed44d9e9575cebaf2fc8/responses.md"

  def teardown
    LlmGateway.reset_configuration!
  end

  def fetch_document
    uri = URI(DOCUMENT_URL)
    response = Net::HTTP.get_response(uri)

    unless response.is_a?(Net::HTTPSuccess)
      raise "Failed to fetch document from #{DOCUMENT_URL}: HTTP #{response.code}"
    end

    response.body.encode("UTF-8", invalid: :replace, undef: :replace)
  end

  def run_two_turn_cache_probe(adapter, options: {})
    document = fetch_document
    first_prompt = <<~PROMPT
      Read the following markdown document and remember it for the next question.

      ---
      #{document}
      ---

      Reply with exactly: loaded
    PROMPT

    first_response = adapter.stream(first_prompt, **options)

    assert_equal "assistant", first_response.role
    assert_nil first_response.error_message

    second_transcript = [
      { role: "user", content: first_prompt },
      first_response.to_h,
      { role: "user", content: "What is this file documenting? Reply in one sentence." }
    ]

    second_response = adapter.stream(second_transcript, **options)

    assert_equal "assistant", second_response.role
    assert_nil second_response.error_message
    second_response
  end

  def assert_cache_hit_on_second_turn(adapter, options: {})
    second_response = run_two_turn_cache_probe(adapter, options: options)

    assert_operator second_response.usage[:cache_read_input_tokens], :>, 0,
      "Expected cache_read_input_tokens > 0 with options #{options.inspect}, got #{second_response.usage.inspect}"
  end

  def assert_no_cache_hit_on_second_turn(adapter, options: {})
    second_response = run_two_turn_cache_probe(adapter, options: options)

    assert_equal 0, second_response.usage[:cache_read_input_tokens].to_i,
      "Expected cache_read_input_tokens to be 0 with options #{options.inspect}, got #{second_response.usage.inspect}"
  end

  def self.define_cache_tests_for(name:, provider:, model:, options: {})
    test "#{name} cache read tokens on second turn" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider:, model:)
          if provider.start_with?("anthropic") && options[:cache_retention].to_s == "none"
            assert_no_cache_hit_on_second_turn(adapter, options: options)
          else
            assert_cache_hit_on_second_turn(adapter, options: options)
          end
        end
      end
    end
  end

  define_cache_tests_for(
    name: "openai_apikey_completions",
    provider: "openai_apikey_completions",
    model: "gpt-5.1",
    options: {
      cache_key: "openai_apikey_completions",
      cache_retention: "short"
    }
  )

  define_cache_tests_for(
    name: "openai_apikey_completions_none",
    provider: "openai_apikey_completions",
    model: "gpt-5.1",
    options: {
      cache_key: "openai_apikey_completions_none",
      cache_retention: "none"
    }
  )

  define_cache_tests_for(
    name: "openai_apikey_responses",
    provider: "openai_apikey_responses",
    model: "gpt-5.4",
    options: {
      cache_key: "openai_apikey_responses",
      cache_retention: "short"
    }
  )

  define_cache_tests_for(
    name: "openai_apikey_responses_none",
    provider: "openai_apikey_responses",
    model: "gpt-5.4",
    options: {
      cache_key: "openai_apikey_responses_none",
      cache_retention: "none"
    }
  )

  define_cache_tests_for(
    name: "openai_oauth_codex",
    provider: "openai_oauth_codex",
    model: "gpt-5.4",
    options: {
      cache_key: "openai_oauth_codex"
    }
  )

  define_cache_tests_for(
    name: "anthropic_apikey_messages",
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514",
    options: {
      cache_retention: "short"
    }
  )

  define_cache_tests_for(
    name: "anthropic_apikey_messages_none",
    provider: "anthropic_apikey_messages",
    model: "claude-sonnet-4-20250514",
    options: {
      cache_retention: "none"
    }
  )
end
