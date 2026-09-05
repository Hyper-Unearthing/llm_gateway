# frozen_string_literal: true

require "test_helper"
require "llm_gateway/agents/tools/tool_utils"

class ToolUtilsTest < Test
  test "tail truncation does not split a multibyte UTF-8 character" do
    result = ToolUtils.truncate_tail("prefix😀suffix", max_bytes: 8)

    assert_equal "suffix", result[:content]
    assert_equal Encoding::UTF_8, result[:content].encoding
    assert_predicate result[:content], :valid_encoding?
    assert_operator result[:content].bytesize, :<=, 8
  end

  test "tail truncation retains a complete multibyte UTF-8 character" do
    result = ToolUtils.truncate_tail("prefix😀suffix", max_bytes: 10)

    assert_equal "😀suffix", result[:content]
    assert_equal Encoding::UTF_8, result[:content].encoding
    assert_predicate result[:content], :valid_encoding?
    assert_equal 10, result[:output_bytes]
  end
end
