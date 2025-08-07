# frozen_string_literal: true

require "test_helper"

class DocumentUsageTest < Test
  test "claude document usage" do
    message = [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "file", data: "abc\n", media_type: "text/plain", name: "small.txt"  } ] } ]
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "claude-sonnet-4-20250514",
        message,
      )
      assert("abc", result[:choices][0][:content][0][:text])
    end
  end

  test "openai document usage" do
    # plain text apparently uses pdg mime type
    message = [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "file", data: "abc\n", media_type: "text/plain", name: "small.txt"  } ] } ]
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.chat(
        "o4-mini",
        message,
      )
      assert("abc", result[:choices][0][:content][0][:text])
    end
  end
end
