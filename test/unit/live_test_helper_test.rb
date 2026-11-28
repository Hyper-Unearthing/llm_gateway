# frozen_string_literal: true

require "test_helper"
require_relative "../utils/live_test_helper"

class LiveTestHelperTest < Test
  include LiveTestHelper

  test "decision adapters use public definitions and replay credentials without proxy registration" do
    ENV.stubs(:[]).returns(nil)
    live_adapter = load_provider(
      provider: LlmGateway::Adapters::Cloudflare::Decisions, model: "@cf/cloudflare/clef", replaying_vcr: true
    )
    assert_instance_of LlmGateway::Adapters::Cloudflare::DecisionsAdapter, live_adapter.adapter
    assert_equal "vcr-replay-token", live_adapter.adapter.client.api_key
    assert_equal "vcr-replay-account", live_adapter.adapter.client.account_id
    assert_equal "@cf/cloudflare/clef", live_adapter.model.id
  end

  test "live Cloudflare decisions accept the configured Workers AI token" do
    ENV.stubs(:[]).returns(nil)
    ENV.stubs(:[]).with("CLOUDFLARE_ACCOUNT_ID").returns("account123")
    ENV.stubs(:[]).with("CLOUDFLARE_AI_API_KEY").returns("workers-ai-token")
    live_adapter = load_provider(provider: LlmGateway::Adapters::Cloudflare::Decisions, model: "@cf/cloudflare/clef")
    assert_equal "workers-ai-token", live_adapter.adapter.client.api_key
    assert_equal "account123", live_adapter.adapter.client.account_id
  end

  test "missing live decision credentials skip before making a request" do
    ENV.stubs(:[]).returns(nil)
    assert_raises(Minitest::Skip) do
      load_provider(provider: LlmGateway::Adapters::OpenAI::Decisions, model: "gpt-6-luna")
    end
    assert_raises(Minitest::Skip) do
      load_provider(provider: LlmGateway::Adapters::Cloudflare::Decisions, model: "@cf/cloudflare/clef")
    end
  end

  test "live decision wrapper supplies its catalog model" do
    request = LlmGateway::DecisionRequest.new(
      message: "Text", questions: { urgent: LlmGateway::PredicateQuestion.new(instructions: "Urgent?") }
    )
    model = LlmGateway.models.fetch("openai/gpt-6-luna")
    adapter = mock
    response = Object.new
    adapter.expects(:decide).with(request, model: model).returns(response)
    assert_same response, LiveAdapter.new(adapter, model).decide(request)
  end

  test "stable handoff results omit normalized costs but preserve unrelated cost fields" do
    result = {
      timestamp: 1_716_650_000_000,
      usage: {
        input: 10,
        cost: { input: BigDecimal("0.001"), total: BigDecimal("0.001") },
        raw: { cost: "provider-value" }
      },
      content: [ { type: "text", cost: "user-content" } ]
    }

    stable = stable_handoff_result(result)

    refute stable.key?("timestamp")
    refute stable.fetch("usage").key?("cost")
    assert_equal "provider-value", stable.dig("usage", "raw", "cost")
    assert_equal "user-content", stable.dig("content", 0, "cost")
  end
end
