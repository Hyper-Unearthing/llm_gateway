# frozen_string_literal: true

require "test_helper"
require "open3"
require "rbconfig"

class UtilsCoreExtTest < Test
  def test_blank_present_and_presence_match_active_support_basics
    assert_nil nil.presence
    assert nil.blank?
    assert false.blank?
    refute true.blank?
    refute 0.blank?
    assert " \t\n".blank?
    assert "\u00A0".blank?
    refute "hello".blank?
    assert [].blank?
    assert({}.blank?)

    assert "hello".present?
    refute "".present?
    assert_equal "hello", "hello".presence
    assert_nil "".presence
  end

  def test_presence_respects_custom_blank_predicate
    credentials_class = Class.new do
      attr_accessor :uid

      def blank?
        uid.blank?
      end
    end
    credentials = credentials_class.new

    refute credentials.present?
    assert_nil credentials.presence

    credentials.uid = "client-id"
    assert credentials.present?
    assert_same credentials, credentials.presence
  end

  def test_presence_respects_custom_present_predicate
    value = Object.new
    def value.present? = false

    assert_nil value.presence
  end

  def test_loading_utils_preserves_existing_presence_methods
    # A separate process checks the Rails-first load order without mutating
    # core methods in the test runner or depending on ActiveSupport.
    script = <<~RUBY
      class Object
        def blank? = :existing_blank
        def present? = :existing_present
        def presence = :existing_presence
      end
      require #{File.expand_path("../../lib/llm_gateway/utils", __dir__).inspect}
      value = Object.new
      abort "existing methods overwritten" unless
        [value.blank?, value.present?, value.presence] ==
          [:existing_blank, :existing_present, :existing_presence]
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, "-e", script)

    assert status.success?, output
  end

  def test_hash_key_helpers_symbolize_nested_hashes_and_arrays
    hash = {
      "outer" => { "inner" => 1 },
      "items" => [ { "name" => "first" } ],
      1 => "kept"
    }

    assert_equal({ outer: { inner: 1 }, items: [ { name: "first" } ], 1 => "kept" }, hash.deep_symbolize_keys)
    assert_equal({ outer: { "inner" => 1 }, items: [ { "name" => "first" } ], 1 => "kept" }, hash.symbolize_keys)
  end

  def test_bang_hash_key_helpers_mutate_receiver
    hash = { "outer" => { "inner" => 1 } }

    assert_same hash, hash.deep_symbolize_keys!
    assert_equal({ outer: { inner: 1 } }, hash)
  end
end
