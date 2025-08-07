# frozen_string_literal: true

require "test_helper"
require "ostruct"

class VcrJsonMatcherTest < Test
  test "matches JSON bodies with different key ordering" do
    # Simulate two requests with the same JSON content but different key ordering
    request1 = OpenStruct.new(
      headers: { "Content-Type" => [ "application/json" ] },
      body: '{"name":"John","age":30,"city":"NYC"}'
    )

    request2 = OpenStruct.new(
      headers: { "Content-Type" => [ "application/json" ] },
      body: '{"age":30,"city":"NYC","name":"John"}'
    )

    # Test that our helper methods work correctly
    assert vcr_json_content_type?(request1)
    assert vcr_json_content_type?(request2)

    parsed1 = vcr_parse_json_body(request1)
    parsed2 = vcr_parse_json_body(request2)

    assert_equal parsed1, parsed2
    assert_equal({ "name" => "John", "age" => 30, "city" => "NYC" }, parsed1)
    assert_equal({ "name" => "John", "age" => 30, "city" => "NYC" }, parsed2)
  end

  test "falls back to string comparison for non-JSON bodies" do
    request1 = OpenStruct.new(
      headers: { "Content-Type" => [ "text/plain" ] },
      body: "Hello World"
    )

    request2 = OpenStruct.new(
      headers: { "Content-Type" => [ "text/plain" ] },
      body: "Hello World"
    )

    assert_equal false, vcr_json_content_type?(request1)
    assert_equal false, vcr_json_content_type?(request2)

    # Should return nil for non-JSON content types
    assert_nil vcr_parse_json_body(request1)
    assert_nil vcr_parse_json_body(request2)
  end

  test "handles malformed JSON gracefully" do
    request = OpenStruct.new(
      headers: { "Content-Type" => [ "application/json" ] },
      body: '{"invalid": json}'
    )

    assert vcr_json_content_type?(request)

    # Should return original body when JSON parsing fails
    assert_equal '{"invalid": json}', vcr_parse_json_body(request)
  end
end
