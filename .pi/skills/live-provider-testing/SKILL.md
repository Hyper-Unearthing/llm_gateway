---
name: live-provider-testing
description: Use when adding or updating llm_gateway live provider integration tests, stream tests, recorded handoff fixtures, or handoff tests that replay outputs across provider/model pairs.
---

# Live Provider Testing

Use this skill when working on live integration tests under `test/integration/live/`, especially tests that validate multiple provider/model pairs, record final stream outputs, or create handoff tests from those recordings.

## Core pattern

Live provider tests use a shared `PAIRS` constant and generate one test per provider/model pair.

```ruby
PAIRS = [
  { provider: "openai_apikey_completions", model: "gpt-5.1" },
  { provider: "anthropic_apikey_messages", model: "claude-sonnet-4-20250514" },
  { provider: "openai_apikey_responses", model: "gpt-5.4" },
  { provider: "anthropic_oauth_messages", model: "claude-sonnet-4-20250514" },
  { provider: "openai_oauth_codex", model: "gpt-5.4" }
].freeze
```

Define tests by iterating over `PAIRS`, not by manually repeating calls:

```ruby
def self.define_stream_tests_for(provider:, model:)
  test "live_text_streaming_#{provider}_#{model}" do
    with_vcr_adapter(provider:, model:) do |adapter|
      response = basic_streaming_text_test(adapter)
      record_live_handoff_result(test_file: __FILE__, provider:, model:, result: response)
    end
  end
end

PAIRS.each do |pair|
  define_stream_tests_for(provider: pair[:provider], model: pair[:model])
end
```

Always include `LiveTestHelper` and reset configuration in teardown:

```ruby
include LiveTestHelper

def teardown
  LlmGateway.reset_configuration!
end
```

## Running adapters

Use `with_vcr_adapter(provider:, model:)` for live/VCR-backed provider tests. It handles:

- provider configuration
- API key and OAuth credential lookup
- VCR cassette naming
- replay tokens for OAuth providers
- authentication skips

Do not construct provider clients directly inside live tests unless the test specifically targets client construction.

## Stream tests that record outputs

The stream tests currently record final results for later handoff tests:

- `test/integration/live/stream_image_test.rb`
- `test/integration/live/stream_reasoning_test.rb`
- `test/integration/live/stream_test.rb`

Their helper methods should return the final `AssistantMessage` response after assertions pass. Generated tests then call:

```ruby
record_live_handoff_result(test_file: __FILE__, provider:, model:, result: response)
```

This writes JSON under:

```text
test/fixtures/handoff/{source_test_name_without_rb}/{provider_model}.json
```

Example:

```text
test/fixtures/handoff/stream_test/openai_apikey_completions_gpt-5.1.json
```

The JSON file is keyed by the current Minitest test name with the `test_` prefix removed, so multiple generated tests for the same pair can share one pair file.

## Handoff tests from recorded stream outputs

Handoff stream tests are separate files and must not modify the existing handoff tests:

- Existing handoff tests to leave alone:
  - `test/integration/live/handoff_test.rb`
  - `test/integration/live/handoff_media_test.rb`
- Stream handoff tests:
  - `test/integration/live/handoff_stream_image_test.rb`
  - `test/integration/live/handoff_stream_reasoning_test.rb`
  - `test/integration/live/handoff_stream_test.rb`

Each stream handoff test should:

1. Read `PAIRS` from the source stream test file.
2. Load all recorded output JSON files from the matching fixture directory.
3. Send those recorded outputs to each provider/model pair.
4. Assert that the receiving model understood the previous outputs.

Important: the prompt must not interpolate `records.length` or otherwise tell the model the count. The model should infer the count from the supplied JSON/transcript. It is fine for the assertion to compare against `records.length.to_s`.

Example prompt style:

```ruby
prompt = <<~PROMPT
  You are receiving recorded final outputs from previous image streaming tests.
  Each output describes the same image. Read the JSON, infer what all previous assistants saw,
  and answer in one short sentence. Include the shape, color, and the number of recorded outputs
  as an Arabic numeral.

  #{JSON.pretty_generate(records)}
PROMPT
```

Example assertions:

```ruby
text = response.content.select { |block| block.type == "text" }.map(&:text).join(" ").downcase
assert_includes text, "red"
assert_includes text, "circle"
assert_includes text, records.length.to_s
```

## Reading pairs from source tests

When creating a handoff test from a source stream test, keep the provider matrix coupled to the source test by reading its `PAIRS` definition:

```ruby
SOURCE_TEST_PATH = File.expand_path("stream_image_test.rb", __dir__)
PAIRS = eval(File.read(SOURCE_TEST_PATH).match(/PAIRS = (\[.*?\])\s*\.freeze/m)[1]).freeze
```

Only use this pattern for test code where the source file is trusted repository code.

## Fixture loading pattern

Handoff tests should skip cleanly if recordings do not exist:

```ruby
def load_recorded_outputs
  skip "Missing fixture directory at #{FIXTURE_DIR}. Run stream_image_test live tests first." unless Dir.exist?(FIXTURE_DIR)

  Dir.glob(File.join(FIXTURE_DIR, "*.json")).sort.map do |path|
    {
      pair: File.basename(path, ".json"),
      result: JSON.parse(File.read(path))
    }
  end.tap do |records|
    skip "No recorded outputs in #{FIXTURE_DIR}. Run stream_image_test live tests first." if records.empty?
  end
end
```

## Validation expectations

Use assertions that prove semantic handoff, not exact wording:

- Image handoff: assert the response mentions `red`, `circle`, and the inferred fixture count.
- Reasoning handoff: assert the response mentions `69` and the inferred fixture count.
- General stream handoff: assert the response mentions the inferred fixture count and expected tool/math results such as `42`, `714`, and `887`.

Avoid brittle assertions against full response text.

## Syntax and test checks

After editing Ruby tests, at minimum run syntax checks:

```bash
ruby -c test/integration/live/<file>.rb
ruby -c test/utils/live_test_helper.rb
```

Run the actual live tests only when requested or when credentials/VCR setup is available, since they may require API keys, OAuth credentials, and network access.
