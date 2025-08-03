# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "llm_gateway"
require "minitest/autorun"
require "vcr"
require "webmock"

include WebMock::API
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

VCR.configure do |config|
  config.allow_http_connections_when_no_cassette = false
  config.cassette_library_dir = File.expand_path("../test/fixtures/vcr_cassettes", __dir__)
  config.hook_into(:webmock)
  config.default_cassette_options = { match_requests_on: %i[body method] }
  config.filter_sensitive_data("<BEARER_TOKEN>") do |interaction|
    auths = interaction.request.headers["Authorization"]&.first || interaction.request.headers["X-Api-Key"]&.first
    if auths && (match = auths.match(/^Bearer\s+([^,\s]+)/))
      match.captures.first
    elsif auths&.start_with?("sk")
      auths
    end
  end
end

def vcr_cassette_name(test_method_name = nil)
  # Find the test file in the call stack (skip test_helper.rb and VCR internal files)
  caller_info = caller.find do |line|
    line.include?("test/") &&
      line.include?(".rb:") &&
      !line.include?("test_helper.rb") &&
      !line.include?("vcr") &&
      !line.include?("minitest")
  end

  if caller_info
    file_path = caller_info.split(":").first
    # Remove the test/ prefix if it exists
    relative_path = file_path.sub(%r{^test/}, "")
    test_name = test_method_name || method_name
    "#{relative_path}/#{test_name}"
  else
    # Fallback: try to get test name from method_name
    test_method_name || method_name || "unknown_test"
  end
end

def assert_hash(expected, actual)
  assertable_actual = actual.respond_to?(:with_indifferent_access) ? actual.with_indifferent_access : actual
  expected.each do |key, value|
    if value.nil?
      assert_nil(assertable_actual[key], "expected #{key} to be nil")
    elsif value.is_a?(Hash)
      assert_hash(value, assertable_actual[key])
    elsif value.is_a?(Array)
      assert_equal(value.size, assertable_actual[key].size, "expected array size of #{key} to equal")
      value.each_with_index do |item, index|
        if item.is_a?(Hash)
          assert_hash(item, assertable_actual[key][index])
        else
          assert_equal(item, assertable_actual[key][index], "expected array item #{index} of #{key} to equal")
        end
      end
    else
      assert_equal(value, assertable_actual[key], "expected #{key} to equal")
    end
  end
end

require "mocha/minitest"

# Test helper method similar to Rails test syntax
def test(name, &block)
  method_name = "test_#{name.downcase.gsub(/[^a-z0-9]/, "_").squeeze("_")}"
  define_method(method_name) do
    # Add method_name method for VCR cassette naming - matches Rails test naming convention
    define_singleton_method(:method_name) { "test_#{name.downcase.gsub(/[^a-z0-9]/, "_").squeeze("_")}" }
    instance_eval(&block)
  end
end

# Add teardown method support
def teardown(&block)
  define_method(:teardown, &block)
end
