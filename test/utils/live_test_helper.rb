# frozen_string_literal: true

require "json"
require "fileutils"

if ENV["LLM_GATEWAY_LIVE_ARTIFACT_DIR"] || ENV["LLM_GATEWAY_LIVE_RECORD"] == "1"
  VCR.configure do |config|
    if ENV["LLM_GATEWAY_LIVE_ARTIFACT_DIR"]
      config.cassette_library_dir = File.join(ENV.fetch("LLM_GATEWAY_LIVE_ARTIFACT_DIR"), "vcr_cassettes")
    end
    if ENV["LLM_GATEWAY_LIVE_RECORD"] == "1"
      config.default_cassette_options = config.default_cassette_options.merge(record: :all)
    end
  end
end

module LiveTestHelper
  LiveAdapter = Struct.new(:adapter, :model) do
    def chat(message, tools: nil, system: nil, **options)
      adapter.chat(message, tools: tools, system: system, model: model, **options)
    end

    def stream(message, tools: nil, system: nil, **options, &block)
      adapter.stream(message, tools: tools, system: system, model: model, **options, &block)
    end

    def method_missing(name, *args, **kwargs, &block)
      if adapter.respond_to?(name)
        adapter.public_send(name, *args, **kwargs, &block)
      else
        super
      end
    end

    def respond_to_missing?(name, include_private = false)
      adapter.respond_to?(name, include_private) || super
    end
  end

  def load_provider(provider:, model:, replaying_vcr: false)
    return load_local_provider if local_provider_override?(provider)

    config = replaying_vcr ? { "api_key" => "vcr-replay-token" } : {}

    adapter_class = LlmGateway::Proxy::Protocol.load_adapter(provider)
    definition = LlmGateway.models.fetch(provider: adapter_class.provider, id: model)

    LiveAdapter.new(adapter_class.build(**config), definition)
  end

  def with_vcr_adapter(provider:, model:, redact_request_body: false)
    cassette_name = vcr_cassette_name
    cassette_name = "qwen-local/#{cassette_name}" if local_provider_override?(provider)
    match_requests_on = redact_request_body ? %i[method uri] : %i[method uri json_body]
    replaying_vcr = ENV["LLM_GATEWAY_LIVE_RECORD"] != "1" && File.exist?(vcr_cassette_path(cassette_name))

    cassette_options = { match_requests_on: match_requests_on }
    cassette_options[:record] = :all if ENV["LLM_GATEWAY_LIVE_RECORD"] == "1"
    cassette_options[:tag] = :redact_large_request_body if redact_request_body

    VCR.use_cassette(cassette_name, cassette_options) do
      yield load_provider(provider: provider, model: model, replaying_vcr: replaying_vcr)
    end
  end

  # Reuse existing Chat Completions scenarios against a configured local provider.
  def local_provider_override?(provider)
    ENV["LLM_GATEWAY_LIVE_LOCAL"] == "1" && provider == "openai-completions"
  end

  def load_local_provider
    model_id = ENV.fetch("LOCAL_LLM_MODEL", "qwen3.8-27b")
    definition = LlmGateway.models.find(provider: "qwen-local", id: model_id) || LlmGateway.models.register(
      provider: "qwen-local", id: model_id,
      context_window: 49_152, max_output_tokens: 8192,
      input_modalities: [ :text ], output_modalities: [ :text ],
      capabilities: { text_generation: true, tool_calling: true, reasoning: false }
    )
    provider = LlmGateway::Providers.chat_completions(
      id: "qwen-local",
      base_endpoint: ENV.fetch("LOCAL_LLM_BASE_URL", "http://127.0.0.1:8080/v1"),
      api_key: ENV["LOCAL_LLM_API_KEY"],
      option_mapper: LlmGateway::ProviderOptions.new(
        allowed: %i[max_completion_tokens temperature top_p top_k min_p stream_options chat_template_kwargs],
        defaults: {
          max_completion_tokens: 8192,
          stream_options: { include_usage: true },
          chat_template_kwargs: { enable_thinking: false }
        }
      )
    )
    LiveAdapter.new(provider.build, definition)
  end

  def assert_stream_message_end_matches_response(message_end_event, response)
    refute_nil message_end_event, "message_end event occurred"
    assert_instance_of AssistantMessage, message_end_event.message
    assert_same response, message_end_event.message
    assert_equal response.to_h, message_end_event.message.to_h
    refute_empty message_end_event.message.provider
    refute_empty message_end_event.message.api
  end

  def assert_usage_costs(response)
    usage = response.usage
    cost = usage[:cost]

    if response.provider == "qwen-local"
      assert_nil cost, "Local models have no catalog API pricing"
      return
    end

    refute_nil cost, "Expected a catalog cost breakdown, got usage #{usage.inspect}"

    %i[input output].each do |bucket|
      next unless usage[bucket].to_i.positive?

      assert_operator cost[bucket], :>, 0, "Expected a positive #{bucket} cost for usage #{usage.inspect}"
    end

    if usage[:cache_read].to_i.positive?
      assert_operator cost[:cache_read], :>, 0, "Expected a positive cache-read cost for usage #{usage.inspect}"

      if usage[:input].to_i.positive?
        cache_read_rate = cost[:cache_read] / usage[:cache_read]
        input_rate = cost[:input] / usage[:input]
        refute_equal input_rate, cache_read_rate, "Cache reads must not use the normal input-token rate"
      end
    end

    assert_equal cost.values_at(:input, :output, :cache_read, :cache_write).sum, cost[:total]
  end

  def record_live_handoff_result(test_file:, provider:, model:, result:)
    if local_provider_override?("openai-completions") && provider == "openai_apikey_completions"
      provider = "qwen-local"
      model = ENV.fetch("LOCAL_LLM_MODEL", "qwen3.8-27b")
    end
    root = ENV["LLM_GATEWAY_LIVE_ARTIFACT_DIR"] || File.expand_path("../fixtures", __dir__)
    fixture_dir = File.join(root, "handoff", File.basename(test_file, ".rb"))
    FileUtils.mkdir_p(fixture_dir)

    pair_name = "#{provider}_#{model}".gsub(/[^A-Za-z0-9_.-]+/, "_")
    path = File.join(fixture_dir, "#{pair_name}.json")
    File.write(path, JSON.pretty_generate(stable_handoff_result(result)) + "\n")
  end

  def stable_handoff_result(result)
    remove_handoff_metadata(jsonable_live_result(result))
  end

  def deep_symbolize(value)
    case value
    when Array
      value.map { |item| deep_symbolize(item) }
    when Hash
      value.each_with_object({}) { |(key, item), acc| acc[key.to_sym] = deep_symbolize(item) }
    else
      value
    end
  end

  def remove_handoff_metadata(value, parent_key: nil)
    case value
    when Array
      value.map { |item| remove_handoff_metadata(item, parent_key:) }
    when Hash
      value.each_with_object({}) do |(key, item), acc|
        next if key == "timestamp"
        next if parent_key == "usage" && key == "cost"

        acc[key] = remove_handoff_metadata(item, parent_key: key)
      end
    else
      value
    end
  end

  def jsonable_live_result(value)
    case value
    when Array
      value.map { |item| jsonable_live_result(item) }
    when Hash
      value.each_with_object({}) { |(key, item), acc| acc[key.to_s] = jsonable_live_result(item) }
    else
      value.respond_to?(:to_h) ? jsonable_live_result(value.to_h) : value
    end
  end

  def vcr_cassette_path(cassette_name)
    direct_path = File.join(VCR.configuration.cassette_library_dir, "#{cassette_name}.yml")
    return direct_path if File.exist?(direct_path)

    # VCR sanitizes path segments like `stream_test.rb` to `stream_test_rb`.
    File.join(VCR.configuration.cassette_library_dir, "#{cassette_name.tr('.', '_')}.yml")
  end
end
