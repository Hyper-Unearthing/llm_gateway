# frozen_string_literal: true

require "test_helper"

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
