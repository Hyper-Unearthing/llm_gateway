# frozen_string_literal: true

require "test_helper"
require_relative "../utils/live_test_helper"

class LiveTestHelperTest < Test
  include LiveTestHelper

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
