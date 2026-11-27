# frozen_string_literal: true

require "test_helper"

class DecisionsTest < Minitest::Test
  def setup
    @team = LlmGateway::ChoiceQuestion.new(
      instructions: "Which team should handle this?",
      criteria: { billing: "Charges and invoices", support: "Technical issues" }
    )
    @urgent = LlmGateway::PredicateQuestion.new(instructions: "Is this urgent?")
    @severity = LlmGateway::ScoreQuestion.new(instructions: "How severe?", criteria: [ "Minor", "Major", "Critical" ])
    @request = LlmGateway::DecisionRequest.new(
      message: "I was charged twice.", questions: { team: @team, urgent: @urgent, severity: @severity }
    )
  end

  def teardown
    WebMock.reset!
  end

  def test_typed_questions_and_string_identifiers
    assert_equal "choice", @team.type
    assert_equal "predicate", @urgent.type
    assert_equal "score", @severity.type
    assert_equal %w[billing support], @team.criteria.keys
    assert_equal %w[team urgent severity], @request.questions.keys
    assert_equal @team, @request.questions.fetch("team")
  end

  def test_question_validation
    assert_raises(Dry::Struct::Error) { LlmGateway::PredicateQuestion.new(instructions: "") }
    assert_raises(ArgumentError) { LlmGateway::ChoiceQuestion.new(instructions: "Team?", criteria: {}) }
    assert_raises(ArgumentError) { LlmGateway::ChoiceQuestion.new(instructions: "Team?", criteria: { a: "Only" }) }
    assert_raises(Dry::Struct::Error) { LlmGateway::ScoreQuestion.new(instructions: "Rate?", criteria: [ "Only" ]) }
    assert_raises(Dry::Struct::Error) { LlmGateway::ScoreQuestion.new(instructions: "Rate?", criteria: Array.new(11, "Level")) }
    assert_raises(Dry::Struct::Error) { LlmGateway::ChoiceQuestion.new(instructions: "Team?", criteria: { a: nil, b: "B" }) }
  end

  def test_request_validation
    assert_raises(ArgumentError) { LlmGateway::DecisionRequest.new(message: "Text", questions: { "" => @team }) }
    assert_raises(Dry::Struct::Error) { LlmGateway::DecisionRequest.new(message: { body: "Text" }, questions: { team: @team }) }
    assert_raises(Dry::Struct::Error) { LlmGateway::DecisionRequest.new(message: "Text", questions: { team: {} }) }
  end

  def test_requests_can_be_built_incrementally_without_mutating_the_base
    base = LlmGateway::DecisionRequest.new(message: "I was charged twice.")
    routing = base.with_question(:team, @team)
    combined = routing.with_question(:urgent, @urgent).with_question(:severity, @severity)
    alternate = base.with_question("urgent", @urgent)

    assert_empty base.questions
    assert_equal [ "team" ], routing.questions.keys
    assert_equal [ "urgent" ], alternate.questions.keys
    assert_equal @request.to_h, combined.to_h
    assert_same @team, combined.questions.fetch("team")
    assert_same @urgent, combined.questions.fetch("urgent")
    assert_equal "I was charged twice.", combined.message
    refute_same base, routing
    refute_same routing.questions, combined.questions
  end

  def test_with_question_rejects_duplicate_names_including_symbol_string_equivalents
    request = LlmGateway::DecisionRequest.new(message: "Text", questions: { team: @team })
    assert_raises(ArgumentError) { request.with_question(:team, @urgent) }
    assert_raises(ArgumentError) { request.with_question("team", @urgent) }
    assert_same @team, request.questions.fetch("team")
  end

  def test_with_question_validates_names_and_question_types
    request = LlmGateway::DecisionRequest.new(message: "Text", questions: {})
    assert_raises(ArgumentError) { request.with_question("", @team) }
    assert_raises(ArgumentError) { request.with_question(nil, @team) }
    assert_raises(Dry::Struct::Error) { request.with_question(:team, {}) }
    assert_empty request.questions
  end

  def test_decide_rejects_empty_requests_before_calling_the_client
    [
      [ LlmGateway::Adapters::TypeSafe::Decisions, "typesafe/jev-latest", {} ],
      [ LlmGateway::Adapters::Cloudflare::Decisions, "cloudflare/@cf/cloudflare/clef", { account_id: "account123" } ],
      [ LlmGateway::Adapters::OpenAI::Decisions, "openai/gpt-6-luna", {} ]
    ].each do |definition, reference, config|
      adapter = definition.build(api_key: "test", **config)
      adapter.client.expects(:decisions).never
      request = LlmGateway::DecisionRequest.new(message: "Text")
      error = assert_raises(ArgumentError) { adapter.decide(request, model: LlmGateway.models.fetch(reference)) }
      assert_equal "At least one question is required", error.message
    end
  end

  def test_system_one_input_mapper
    mapped = LlmGateway::Adapters::Decisions::InputMapper.map(@request)
    assert_equal @request.message, mapped[:state]
    assert_equal({ type: "noul", instructions: "Is this urgent?" }, mapped[:questions]["urgent"])
    assert_equal @team.criteria, mapped[:questions]["team"][:criteria]
    assert_equal @severity.criteria, mapped[:questions]["severity"][:criteria]
  end

  def test_openai_input_mapper
    mapped = LlmGateway::Adapters::OpenAI::Decisions::InputMapper.map(@request)
    assert_equal @request.message, mapped[:input]
    assert_equal({
      name: "team",
      type: "choice",
      instructions: @team.instructions,
      choices: [ { value: "billing", description: "Charges and invoices" }, { value: "support", description: "Technical issues" } ]
    }, mapped[:questions][0])
    assert_equal "predicate", mapped[:questions][1][:type]
    assert_equal [ { label: "0", description: "Minor" }, { label: "1", description: "Major" }, { label: "2", description: "Critical" } ], mapped[:questions][2][:levels]
  end

  def test_system_one_output_mapper
    response = map_system_one(system_one_response)
    assert_instance_of LlmGateway::DecisionResponse, response
    assert_instance_of LlmGateway::ChoiceAnswer, response.answers.team
    assert_equal "billing", response.answers.team.choice
    assert_equal({ "billing" => 0.95, "support" => 0.05 }, response.answers.team.probabilities)
    assert_equal 0.8, response.answers.urgent.probability
    assert_equal 1.1, response.answers.severity.score
    assert_equal({ 0 => 0.1, 1 => 0.7, 2 => 0.2 }, response.answers.severity.probabilities)
    assert_equal({ 0 => "Minor", 1 => "Major", 2 => "Critical" }, response.answers.severity.legend)
    assert_equal "jev-1.14.0", response.model
    assert_equal "decisions", response.api
    assert_equal({
      input: 100,
      cache_read: 0,
      cache_write: 0,
      output: 20,
      total: 120,
      raw: { input_tokens: 100, output_tokens: 20 }
    }, response.usage)
  end

  def test_answers_are_named_immutable_data_records
    response = map_system_one(system_one_response)
    answers = response.answers
    assert_kind_of Data, answers
    assert answers.frozen?
    assert_instance_of LlmGateway::ChoiceAnswer, answers.team
    assert_instance_of LlmGateway::PredicateAnswer, answers.urgent
    assert_instance_of LlmGateway::ScoreAnswer, answers.severity
    refute_respond_to answers, :[]
    refute_respond_to answers, :fetch
    assert_respond_to answers, :team
    refute_respond_to answers, :unknown
    assert_raises(NoMethodError) { answers.unknown }
    assert_raises(NoMethodError) { answers.team = answers.urgent }
    assert_raises(Dry::Struct::MissingAttributeError) { response[:team] }
    assert_equal({ team: answers.team, urgent: answers.urgent, severity: answers.severity }, answers.to_h)
  end

  def test_each_response_uses_its_own_question_set
    first = map_system_one(system_one_response)
    raw = system_one_response
    raw[:answers].delete(:team)
    second = map_system_one(raw)
    assert_respond_to first.answers, :team
    refute_respond_to second.answers, :team
    assert_respond_to second.answers, :urgent
  end

  def test_explicit_hash_conversion_supports_names_that_are_not_convenient_method_calls
    raw = system_one_response
    raw[:answers]["support-team"] = raw[:answers].delete(:team)
    response = map_system_one(raw)
    assert_equal "billing", response.answers.to_h.fetch(:"support-team").choice
  end

  def test_question_names_can_shadow_methods_without_a_reserved_name_policy
    request = LlmGateway::DecisionRequest.new(message: "Text").with_question(:class, @team)
    assert_same @team, request.questions.fetch("class")
    raw = system_one_response
    raw[:answers][:class] = raw[:answers].delete(:team)
    assert_equal "billing", map_system_one(raw).answers.class.choice
  end

  def test_response_serializes_named_answers_to_plain_hashes
    response = map_system_one(system_one_response)
    hash = response.to_h
    assert_instance_of Hash, hash[:answers]
    assert_equal "billing", hash[:answers][:team][:choice]
    assert_equal 0.8, hash[:answers][:urgent][:probability]
    assert_equal "billing", JSON.parse(JSON.generate(hash)).dig("answers", "team", "choice")
  end

  def test_openai_output_mapper
    response = map_openai(openai_response)
    assert_equal "decision_123", response.id
    assert_equal "billing", response.answers.team.choice
    assert_equal 0.8, response.answers.urgent.probability
    assert_equal({ 0 => 0.1, 1 => 0.7, 2 => 0.2 }, response.answers.severity.probabilities)
    assert_equal({ 0 => "Minor", 1 => "Major", 2 => "Critical" }, response.answers.severity.legend)
    assert_equal 80, response.usage[:input]
    assert_equal 20, response.usage[:cache_read]
    assert_equal 120, response.usage[:total]
  end

  def test_openai_answers_are_matched_by_name_not_order
    raw = openai_response
    raw[:answers].reverse!
    assert_equal "billing", map_openai(raw).answers.team.choice
  end

  def test_refusal_is_not_a_fabricated_answer
    raw = openai_response
    raw[:answers][0] = { type: "refusal", name: "team" }
    assert_instance_of LlmGateway::RefusalAnswer, map_openai(raw).answers.team
  end

  def test_provider_answer_names_and_types_are_preserved_without_comparing_to_request
    raw = system_one_response
    raw[:answers][:extra] = raw[:answers].delete(:team)
    response = map_system_one(raw)
    refute response.answers.to_h.key?(:team)
    assert_equal "billing", response.answers.extra.choice

    raw = system_one_response
    raw[:answers][:urgent] = raw[:answers].delete(:team)
    assert_instance_of LlmGateway::ChoiceAnswer, map_system_one(raw).answers.urgent
  end

  def test_duplicate_answer_names_are_rejected_to_avoid_overwriting_data
    raw = openai_response
    raw[:answers] << raw[:answers].first
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_openai(raw) }

    raw = system_one_response
    raw[:answers]["team"] = raw[:answers][:team]
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_system_one(raw) }
  end

  def test_integer_numeric_fields_and_missing_optional_confidence
    raw = system_one_response
    raw[:answers][:team][:confidence] = 1
    raw[:answers][:urgent][:noul] = 1
    raw[:answers][:severity][:score] = 1
    raw[:answers][:severity].delete(:confidence)
    response = map_system_one(raw)
    assert_equal 1.0, response.answers.team.confidence
    assert_equal 1.0, response.answers.urgent.probability
    assert_equal 1.0, response.answers.severity.score
    assert_nil response.answers.severity.confidence
  end

  def test_provider_values_are_mapped_without_semantic_validation
    raw = system_one_response
    raw[:answers][:urgent][:noul] = 1.1
    raw[:answers][:team][:choice] = "other"
    raw[:answers][:team][:confidence] = -0.1
    raw[:answers][:team][:probabilities] = { other: 1.2 }
    raw[:answers][:severity][:score] = 3.0
    raw[:answers][:severity][:probabilities] = { "4": -0.2 }
    response = map_system_one(raw)
    assert_equal 1.1, response.answers.urgent.probability
    assert_equal "other", response.answers.team.choice
    assert_equal(-0.1, response.answers.team.confidence)
    assert_equal({ "other" => 1.2 }, response.answers.team.probabilities)
    assert_equal 3.0, response.answers.severity.score
    assert_equal({ 4 => -0.2 }, response.answers.severity.probabilities)
  end

  def test_distributions_are_not_validated_or_renormalized
    [ 0.1, 0.9 ].each do |value|
      raw = system_one_response
      raw[:answers][:team][:probabilities] = { billing: value, support: value }
      raw[:answers][:severity][:probabilities] = { "0": value, "1": value, "2": value }
      response = map_system_one(raw)
      assert_equal [ value, value ], response.answers.team.probabilities.values
      assert_equal [ value, value, value ], response.answers.severity.probabilities.values

      raw = openai_response
      raw[:answers].each do |answer|
        answer[:probabilities]&.each { |entry| entry[:probability] = value }
      end
      response = map_openai(raw)
      assert_equal [ value, value ], response.answers.team.probabilities.values
      assert_equal [ value, value, value ], response.answers.severity.probabilities.values
    end
  end

  def test_duplicate_probability_keys_are_rejected_after_normalization
    raw = system_one_response
    raw[:answers][:team][:probabilities]["billing"] = 0.5
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_system_one(raw) }

    raw = system_one_response
    raw[:answers][:severity][:probabilities][0] = 0.5
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_system_one(raw) }

    raw = openai_response
    raw[:answers][0][:probabilities] << raw[:answers][0][:probabilities].first
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_openai(raw) }

    raw = openai_response
    raw[:answers][2][:probabilities] = [
      { value: 0, probability: 0.2 }, { value: "0", probability: 0.8 }, { value: 1, probability: 0.2 }
    ]
    error = assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_openai(raw) }
    assert_match "Duplicate normalized option", error.message
  end

  def test_score_legends_preserve_provider_descriptions_and_support_unrequested_answers
    raw = system_one_response
    raw[:answers][:severity][:legend] = { "0": "Provider low", "1": "Provider medium", "2": "Provider high" }
    assert_equal "Provider low", map_system_one(raw).answers.severity.legend[0]

    raw = openai_response
    raw[:answers][2][:name] = "extra_severity"
    assert_equal({ 0 => "0", 1 => "1", 2 => "2" }, map_openai(raw).answers.extra_severity.legend)
  end

  def test_unrepresentable_answers_still_fail_during_mapping
    raw = system_one_response
    raw[:answers][:urgent][:noul] = nil
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_system_one(raw) }
    raw = system_one_response
    raw[:answers][:urgent][:type] = "unknown"
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_system_one(raw) }
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_system_one(answers: nil) }
    assert_raises(LlmGateway::Errors::InvalidDecisionResponse) { map_openai(answers: {}) }
  end

  def test_decision_adapters_use_the_existing_definition_and_build_api
    [ LlmGateway::Adapters::OpenAI::Decisions, LlmGateway::Adapters::TypeSafe::Decisions,
      LlmGateway::Adapters::Cloudflare::Decisions ].each do |definition|
      config = { api_key: "test" }
      config[:account_id] = "account123" if definition.provider == "cloudflare"
      adapter = definition.build(**config)
      assert_instance_of definition.adapter_class, adapter
      assert_equal definition.provider, adapter.provider
      assert_instance_of LlmGateway::AdapterDefinition, definition.definition
      assert_equal "test", adapter.client.api_key
    end
  end

  def test_catalog_support_and_model_validation
    model = LlmGateway.models.fetch("typesafe/jev-latest")
    assert_equal true, model.supports?(:decisions)
    assert LlmGateway::Adapters::TypeSafe::Decisions.supports_model?(model)
    assert LlmGateway::Adapters::OpenAI::Decisions.supports_model?(LlmGateway.models.fetch("openai/gpt-6-luna"))
    refute LlmGateway::Adapters::OpenAI::Decisions.supports_model?(LlmGateway.models.fetch("openai/gpt-4o"))
    adapter = LlmGateway::Adapters::TypeSafe::Decisions.build(api_key: "test")
    assert_raises(LlmGateway::Errors::ModelProviderMismatch) { adapter.decide(@request, model: LlmGateway.models.fetch("openai/gpt-6-luna")) }
    assert_raises(ArgumentError) { adapter.decide("not a request", model: model) }
    assert_raises(NotImplementedError) { adapter.stream("text", model: model) }
    assert_raises(NotImplementedError) { adapter.raw_stream("text", model: model) }
  end

  def test_openai_unsupported_model_and_question_limit_fail_before_http
    adapter = LlmGateway::Adapters::OpenAI::Decisions.build(api_key: "test")
    assert_raises(LlmGateway::Errors::UnsupportedModelForAdapter) do
      adapter.decide(@request, model: LlmGateway.models.fetch("openai/gpt-4o"))
    end
    request = LlmGateway::DecisionRequest.new(message: "Text", questions: 401.times.to_h { |i| [ "q#{i}", @urgent ] })
    assert_raises(ArgumentError) { adapter.decide(request, model: LlmGateway.models.fetch("openai/gpt-6-luna")) }
  end

  def test_typesafe_decide_posts_system_one_request
    stub = stub_request(:post, "https://api.typesafe.ai/v1/systemone")
      .with(headers: { "Authorization" => "Bearer test" },
            body: LlmGateway::Adapters::Decisions::InputMapper.map(@request).merge(model: "jev-latest"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(system_one_response))
    adapter = LlmGateway::Adapters::TypeSafe::Decisions.build(api_key: "test")
    response = adapter.decide(@request, model: LlmGateway.models.fetch("typesafe/jev-latest"))
    assert_equal "billing", response.answers.team.choice
    assert_equal "typesafe", response.provider
    assert_equal BigDecimal("0.0000042"), response.usage.dig(:cost, :total)
    assert_equal BigDecimal("0"), response.usage.dig(:cost, :output)
    assert_requested stub
  end

  def test_cloudflare_decide_unwraps_workers_ai_envelope
    %w[clef clef-flash].each do |name|
      model_id = "@cf/cloudflare/#{name}"
      stub = stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/account123/ai/run/#{model_id}")
        .with(headers: { "Authorization" => "Bearer test" },
              body: LlmGateway::Adapters::Decisions::InputMapper.map(@request).merge(model: name))
        .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                   body: JSON.generate(success: true, result: system_one_response.merge(model: name)))
      adapter = LlmGateway::Adapters::Cloudflare::Decisions.build(api_key: "test", account_id: "account123")
      response = adapter.decide(@request, model: LlmGateway.models.fetch(provider: "cloudflare", id: model_id))
      assert_equal "billing", response.answers.team.choice
      assert_equal "cloudflare", response.provider
      expected_cost = name == "clef" ? "0.000024" : "0.0000038"
      assert_equal BigDecimal(expected_cost), response.usage.dig(:cost, :total)
      assert_equal BigDecimal("0"), response.usage.dig(:cost, :output)
      assert_requested stub
    end
  end

  def test_openai_decide_posts_decisions_request
    stub = stub_request(:post, "https://api.openai.com/v1/decisions")
      .with(headers: { "Authorization" => "Bearer test" },
            body: LlmGateway::Adapters::OpenAI::Decisions::InputMapper.map(@request).merge(model: "gpt-6-luna"))
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(openai_response))
    adapter = LlmGateway::Adapters::OpenAI::Decisions.build(api_key: "test")
    response = adapter.decide(@request, model: LlmGateway.models.fetch("openai/gpt-6-luna"))
    assert_equal "billing", response.answers.team.choice
    assert_equal "openai", response.provider
    assert_equal BigDecimal("0.0000082"), response.usage.dig(:cost, :total)
    assert_equal BigDecimal("0"), response.usage.dig(:cost, :output)
    assert_requested stub
  end

  def test_client_errors_are_not_silently_swallowed
    [ [ LlmGateway::Clients::TypeSafe.new(api_key: "test"), "https://api.typesafe.ai/v1/systemone", "jev-latest" ],
      [ LlmGateway::Clients::Cloudflare.new(api_key: "test", account_id: "account123"),
        "https://api.cloudflare.com/client/v4/accounts/account123/ai/run/@cf/cloudflare/clef", "@cf/cloudflare/clef" ] ].each do |client, url, model|
      stub_request(:post, url).to_return(status: 401, body: JSON.generate(error: { message: "Invalid key" }))
      assert_raises(LlmGateway::Errors::AuthenticationError) { client.decisions(state: "Text", questions: {}, model: model) }
    end
  end

  def test_cloudflare_failure_envelope_and_account_validation
    assert_raises(ArgumentError) { LlmGateway::Clients::Cloudflare.new(api_key: "test", account_id: nil) }
    assert_raises(ArgumentError) { LlmGateway::Clients::Cloudflare.new(api_key: "test", account_id: "../bad") }
    client = LlmGateway::Clients::Cloudflare.new(api_key: "test", account_id: "account123")
    stub_request(:post, "https://api.cloudflare.com/client/v4/accounts/account123/ai/run/@cf/cloudflare/clef")
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: JSON.generate(success: false, errors: [ { message: "Failed" } ]))
    assert_raises(LlmGateway::Errors::APIStatusError) { client.decisions(state: "Text", questions: {}, model: "@cf/cloudflare/clef") }
  end

  private

  def map_system_one(raw)
    LlmGateway::Adapters::Decisions::OutputMapper.map(raw, request: @request, provider: "typesafe", model: "jev-latest")
  end

  def map_openai(raw)
    LlmGateway::Adapters::OpenAI::Decisions::OutputMapper.map(raw, request: @request, provider: "openai", model: "gpt-6-luna")
  end

  def system_one_response
    {
      model: "jev-1.14.0",
      answers: {
        team: { type: "choice", choice: "billing", confidence: 0.9, probabilities: { billing: 0.95, support: 0.05 } },
        urgent: { type: "noul", noul: 0.8 },
        severity: { type: "score", score: 1.1, confidence: 0.55, probabilities: { "0": 0.1, "1": 0.7, "2": 0.2 } }
      },
      usage: { input_tokens: 100, output_tokens: 20 }
    }
  end

  def openai_response
    {
      id: "decision_123",
      model: "gpt-6-luna",
      answers: [
        {
          name: "team",
          type: "choice",
          choice: "billing",
          confidence: 0.9,
          probabilities: [ { value: "billing", probability: 0.95 }, { value: "support", probability: 0.05 } ]
        },
        { name: "urgent", type: "predicate", probability: 0.8 },
        {
          name: "severity",
          type: "score",
          score: 1.1,
          confidence: 0.55,
          probabilities: [ { value: 0, label: "0", probability: 0.1 }, { value: 1, label: "1", probability: 0.7 }, { value: 2, label: "2", probability: 0.2 } ]
        }
      ],
      usage: { input_tokens: 100, output_tokens: 20, input_tokens_details: { cached_tokens: 20 } }
    }
  end
end
