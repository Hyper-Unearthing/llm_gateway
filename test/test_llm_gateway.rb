# frozen_string_literal: true

require "test_helper"

class TestLlmGateway < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::LlmGateway::VERSION
  end

  def test_gem_loads_properly
    assert_kind_of Module, LlmGateway
    assert_respond_to LlmGateway::Client, :chat
  end
end
