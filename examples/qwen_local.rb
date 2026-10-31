# frozen_string_literal: true

# Start llama.cpp separately, then run:
#   bundle exec ruby examples/qwen_local.rb "Explain Ruby's Enumerable module."
# Optional: LOCAL_LLM_BASE_URL, LOCAL_LLM_MODEL, LOCAL_LLM_API_KEY.
require "bundler/setup"
require "llm_gateway"

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

model = LlmGateway.models.register(
  provider: provider.provider,
  id: ENV.fetch("LOCAL_LLM_MODEL", "qwen3.8-27b"),
  context_window: 49_152,
  max_output_tokens: 8192,
  input_modalities: [:text],
  output_modalities: [:text],
  capabilities: { text_generation: true, tool_calling: true, reasoning: false }
)

prompt = ARGV.empty? ? "Count from 1 to 3." : ARGV.join(" ")
response = provider.build.stream(prompt, model: model) do |event|
  if %i[text_start text_delta].include?(event.type)
    print event.delta
    $stdout.flush
  end
end
puts
warn "stop=#{response.stop_reason} input=#{response.usage[:input]} output=#{response.usage[:output]}"
warn "Response reached its output limit; increase the allowance or shorten the prompt." if response.stop_reason == "length"
