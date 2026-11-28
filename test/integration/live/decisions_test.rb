# frozen_string_literal: true

require "test_helper"
require_relative "../../utils/live_test_helper"

class LiveDecisionsTest < Test
  include LiveTestHelper

  PAIRS = [
    { name: "cloudflare_clef", provider: LlmGateway::Adapters::Cloudflare::Decisions, model: "@cf/cloudflare/clef" },
    { name: "cloudflare_clef_flash", provider: LlmGateway::Adapters::Cloudflare::Decisions, model: "@cf/cloudflare/clef-flash" },
    { name: "openai_decisions", provider: LlmGateway::Adapters::OpenAI::Decisions, model: "gpt-6-luna" },
    { name: "typesafe_jev", provider: LlmGateway::Adapters::TypeSafe::Decisions, model: "jev-1.14.0" }
  ].freeze

  def decision_request
    LlmGateway::DecisionRequest.new(
      message: "Checkout is completely down. Every customer gets an error when trying to pay, and nobody can place an order. There is no workaround.",
      questions: {
        team: LlmGateway::ChoiceQuestion.new(
          instructions: "Which team should handle this incident?",
          criteria: { billing: "Invoice questions and refund requests", technical: "Broken software, errors and outages", sales: "New plans and upgrades" }
        ),
        urgent: LlmGateway::PredicateQuestion.new(instructions: "Is this an urgent service outage that needs immediate attention?"),
        severity: LlmGateway::ScoreQuestion.new(
          instructions: "How severe is the impact on customers?",
          criteria: [ "Cosmetic only; no lost functionality", "Some degradation; a workaround exists", "All customers blocked; no workaround exists" ]
        )
      }
    )
  end

  def assert_distribution(probabilities, keys:)
    assert_equal keys.sort, probabilities.keys.sort
    probabilities.each_value do |probability|
      assert_operator probability, :>=, 0
      assert_operator probability, :<=, 1
    end
    assert_in_delta 1.0, probabilities.values.sum, 0.02
  end

  def assert_decisions(response, provider:)
    assert_instance_of LlmGateway::DecisionResponse, response
    assert_equal provider, response.provider
    assert_equal "decisions", response.api
    refute_empty response.model
    assert_kind_of Data, response.answers
    assert_equal %i[severity team urgent], response.answers.members.sort

    team = response.answers.team
    assert_instance_of LlmGateway::ChoiceAnswer, team
    assert_equal "technical", team.choice
    assert_distribution(team.probabilities, keys: %w[billing technical sales])
    assert_operator team.probabilities.fetch("technical"), :>, 0.5

    urgent = response.answers.urgent
    assert_instance_of LlmGateway::PredicateAnswer, urgent
    assert_operator urgent.probability, :>, 0.5
    assert_operator urgent.probability, :<=, 1

    severity = response.answers.severity
    assert_instance_of LlmGateway::ScoreAnswer, severity
    assert_operator severity.score, :>, 1.0
    assert_operator severity.score, :<=, 2.0
    assert_distribution(severity.probabilities, keys: [ 0, 1, 2 ])
    expected_score = severity.probabilities.sum { |level, probability| level * probability }
    assert_in_delta expected_score, severity.score, 0.02
    assert_equal decision_request.questions.fetch("severity").criteria, severity.legend.values

    assert_operator response.usage[:input], :>, 0
    cost = response.usage.fetch(:cost)
    assert_operator cost[:input], :>, 0
    assert_equal BigDecimal("0"), cost[:output], "Decision output tokens should be free"
    assert_equal cost.values_at(:input, :output, :cache_read, :cache_write).sum, cost[:total]
  end

  PAIRS.each do |pair|
    test "live_decisions_#{pair[:name]}" do
      with_vcr_adapter(provider: pair[:provider], model: pair[:model]) do |adapter|
        response = adapter.decide(decision_request)
        assert_decisions(response, provider: pair[:provider].provider)
      end
    end
  end
end
