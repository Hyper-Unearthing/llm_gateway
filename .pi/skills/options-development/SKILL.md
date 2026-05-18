---
name: options-development
description: Use when developing or updating provider option mappers in llm_gateway from an API reference URL and optional API hint. Guides managed option mapping, valid option whitelists, source comments, tests, and client behavior boundaries.
---

# Options Development

Use this skill when the user asks to build, update, or audit an LLM provider/API option mapper. The user should provide:

- an API reference URL, e.g. `https://platform.claude.com/docs/en/api/messages/create`
- a hint identifying the API when a provider has multiple APIs, e.g. `Anthropic Messages`, `OpenAI Responses`, `OpenAI Chat Completions`, `Groq Chat Completions`, `OpenAI Codex`

## Goal

Keep option handling split into clear layers:

1. **Managed options**: library-owned options that should work consistently across clients.
2. **Option mapper**: translates managed options to provider/API option names and shapes. If an option is not managed but is a valid provider option, pass it through. Every mapper must validate the final transformed hash against a whitelist of valid provider options and reject unknown keys.
3. **Client behavior**: clients receive already-mapped options and must not do additional option mapping. A client should behave exactly like the provider API docs for its endpoint.
4. **Tools and transcript**: option mappers must not map tools, transcript, messages, or system content.
5. **Current limitation**: mapped options are currently pushed only into the stream path; do not broaden this unless the task explicitly asks for architecture work.

## Current managed options

- `reasoning`
  - supported values: `"none"`, `"low"`, `"medium"`, `"high"`, `"xhigh"`
  - mapped differently depending on the provider/API
- `max_completion_tokens`
  - default is usually `20_480`
  - Anthropic maps this to `max_tokens`
  - OpenAI Responses maps this to `max_output_tokens`
- `response_format`
  - examples: `"text"`, `{ type: "json_object" }`, `{ type: "json_schema" }`
- `cache_key`
  - OpenAI maps this to `prompt_cache_key`
- `cache_retention`
  - OpenAI values: `"short"`, `"long"`, `"none"`
  - Anthropic passes this through as `cache_retention`
- `temperature`
  - Groq defaults this to `0`

These are **not** options and must not be handled by option mappers:

- `message` / `messages` / transcript
- `tools`
- `system`

## Repository locations

Option mappers live under `lib/llm_gateway/adapters/`, including:

- `lib/llm_gateway/adapters/anthropic_option_mapper.rb`
- `lib/llm_gateway/adapters/groq/option_mapper.rb`
- `lib/llm_gateway/adapters/openai/chat_completions/option_mapper.rb`
- `lib/llm_gateway/adapters/openai/responses/option_mapper.rb`
- `lib/llm_gateway/adapters/openai_codex/option_mapper.rb`

Tests live under `test/unit/options/`.

## Required workflow

1. **Identify mapper and tests**
   - Use the API hint to find the corresponding option mapper and test file.
   - Inspect the related adapter/client only to verify mapping boundaries; do not move mapping into clients.

2. **Read the provider API reference**
   - Fetch/read the provided URL if network access is available, for example with `curl -L <url>`.
   - Extract every request-body option accepted by the endpoint.
   - Exclude non-option structural fields such as messages/input/transcript, tools, and system/developer instructions.
   - If docs are not fetchable, say so and ask the user for the relevant request parameter list before coding.

3. **Add/maintain a source comment at the option mapper**
   - Near the valid-option whitelist in the mapper, add a comment containing:
     - source URL
     - API name/hint
     - date accessed
     - the full list of valid option keys copied from the API reference
   - Keep this comment updated whenever the whitelist changes.

4. **Implement managed option mapping in the mapper only**
   - Match the coding style and structure of the closest existing mapper before changing behavior. For example, Anthropic and OpenAI Chat Completions use named default constants, `VALID_OPTIONS`, `MANAGED_OPTIONS`, a `map` method that builds `mapped_options`, explicit normalizer helpers, and `validate_options!` near the mapper.
   - Prefer `mapped_options = options.reject { |key, _| MANAGED_OPTIONS.include?(key) }` when a mapper has multiple managed aliases; this makes alias removal explicit and keeps pass-through provider-native options obvious.
   - Remove managed aliases after mapping so the final hash contains only provider-native option keys.
   - Preserve valid provider-native options that are not managed.
   - Apply provider-specific defaults only in the mapper.
   - Unless the user explicitly asks for default behavior changes, do not modify existing defaults.
   - Do not map tools, transcript/messages, or system.

5. **Whitelist after transformation**
   - Define a `VALID_OPTIONS`/equivalent whitelist from the API reference.
   - After all transformations, reject any final key not in the whitelist.
   - Prefer raising `ArgumentError` with a useful message listing unknown option keys and/or valid keys.
   - Validate the returned hash, not merely the input hash, so bad mapped output is caught.

6. **Tests**
   - Match the structure and naming style of the closest existing provider/API option test before adding cases. For Anthropic and OpenAI Chat Completions, prefer a compact set of broad tests:
     - one adapter-boundary test named like `passes mapped managed options and provider-native options through adapter to client`
     - one unknown provider option rejection test
     - one structural field rejection test
     - one superset/final output mapper test
   - Prefer testing option behavior at the adapter boundary by stubbing the provider client and asserting the exact options passed to the client's request/stream method. This verifies that managed options are mapped before the client and that valid provider-native options pass through the adapter layer unchanged.
   - Keep pure mapper tests for validation/error behavior, final-output superset assertions, and small normalization helpers when useful, but avoid relying only on direct `OptionMapper.map(...)` assertions for passthrough behavior.
   - Fake clients in adapter-boundary stream tests should yield enough realistic stream chunks for the adapter's stream mapper and accumulator to complete without errors; do not yield only terminal/usage chunks if the mapper expects started content/tool state.
   - Add/update tests for:
     - each managed option mapping relevant to the provider/API
     - pass-through of valid provider-native options together with representative managed options in the same adapter-level test
     - rejection of unknown options after transformation
     - no handling of tools/messages/system in the mapper
     - provider-specific defaults, if any
   - For adapter-level option tests:
     - instantiate the real adapter with a fake/stub client for the target provider/API
     - call the public adapter method (`stream` today) with managed and provider-native options
     - capture the keyword args received by the client method
     - assert the final provider-native option hash, including mapped managed options and unchanged provider-native options
     - ensure fake clients provide whatever minimal stream/result events are needed so the adapter can complete without network or VCR
   - After making option-mapper changes, run the targeted option tests, then the broader test suite if practical.
   - If VCR/cassette-backed tests fail and option changes are the only code changes, do not immediately re-record or mutate cassettes. First explain why the VCR is failing (for example: request body changed because a new/default option is now sent, unknown option rejection changed control flow, or provider-native option passthrough altered the recorded request). Ask for confirmation before taking further VCR steps.

## Implementation checklist

Before finishing, verify:

- [ ] mapper has source/API/date/full-valid-option-list comment
- [ ] mapper maps all relevant managed options and deletes aliases
- [ ] valid provider-native options pass through unchanged
- [ ] final returned options are whitelist-validated
- [ ] clients do not perform additional option mapping
- [ ] tools/transcript/messages/system are not mapped as options
- [ ] defaults were not modified unless explicitly requested
- [ ] tests cover mapping, pass-through, rejection, and defaults
- [ ] tests were run after option changes; any VCR failure was explained before further cassette work
