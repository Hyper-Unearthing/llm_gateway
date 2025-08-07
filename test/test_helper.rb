# frozen_string_literal: true

require "dotenv"
Dotenv.load(".env")

require "simplecov"
require "debug"

SimpleCov.start do
  add_filter "/test/"
  add_filter "/vendor/"

  add_group "Core", "lib/llm_gateway.rb"
  add_group "Clients", "lib/llm_gateway/adapters"
  add_group "Base Classes",
            [ "lib/llm_gateway/base_client.rb", "lib/llm_gateway/client.rb", "lib/llm_gateway/prompt.rb" ]
  add_group "Utilities", [ "lib/llm_gateway/errors.rb" ]

  # minimum_coverage 80
  # minimum_coverage_by_file 70
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "llm_gateway"
require "minitest/autorun"
require "vcr"
require "webmock"

include WebMock::API
WebMock.enable!
WebMock.disable_net_connect!(allow_localhost: true)

# Helper methods for VCR JSON matching
def vcr_json_content_type?(request)
  content_type = request.headers["Content-Type"]&.first
  content_type&.include?("application/json")
end

def vcr_parse_json_body(request)
  return nil unless vcr_json_content_type?(request)
  JSON.parse(request.body)
rescue JSON::ParserError
  request.body
end

VCR.configure do |config|
  config.allow_http_connections_when_no_cassette = false
  config.cassette_library_dir = "test/fixtures/vcr_cassettes"
  config.hook_into(:webmock)

  # Custom matcher for JSON bodies that compares parsed JSON instead of raw strings
  config.register_request_matcher(:json_body) do |request_1, request_2|
    # If both requests have JSON content type, compare parsed JSON
    if vcr_json_content_type?(request_1) && vcr_json_content_type?(request_2)
      parsed_body_1 = vcr_parse_json_body(request_1)
      parsed_body_2 = vcr_parse_json_body(request_2)
      parsed_body_1 == parsed_body_2
    else
      # Fall back to string comparison for non-JSON bodies
      request_1.body == request_2.body
    end
  end

  config.default_cassette_options = { match_requests_on: %i[json_body method] }
  config.filter_sensitive_data("<BEARER_TOKEN>") do |interaction|
    auths = interaction.request.headers["Authorization"]&.first || interaction.request.headers["X-Api-Key"]&.first
    if auths && (match = auths.match(/^Bearer\s+([^,\s]+)/))
      match.captures.first
    elsif auths&.start_with?("sk")
      auths
    end
  end
end

def vcr_cassette_name(test_method_name = self.name)
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
    # Convert to relative path and remove test/ prefix - handle both absolute and relative paths
    if file_path.include?("/test/")
      relative_path = file_path.sub(%r{.*/test/}, "")
    else
      # Handle case where we already have a relative path from test/
      relative_path = file_path.sub(%r{^test/}, "")
    end
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


# Add teardown method support
def teardown(&block)
  define_method(:teardown, &block)
end


class Test < Minitest::Test
  def self.test(name, &block)
    test_name = "test_#{name.gsub(/\s+/, '_')}".to_sym
    defined = method_defined? test_name
    raise "#{test_name} is already defined in #{self}" if defined
    if block_given?
      define_method(test_name, &block)
    else
      define_method(test_name) do
        flunk "No implementation provided for #{name}"
      end
    end
  end
end
