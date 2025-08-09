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

  test "cluade upload file" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.upload_file("anthropic", filename: "test.txt", content: "Hello, world!", mime_type: "text/plain")
      assert_equal(result, { id: "file_011CRub6FQG7ympTxXw81mic", size_bytes: 13, created_at: "2025-08-08T04:10:55.298000Z", filename: "test.txt", mime_type: "application/octet-stream", downloadable: false, expires_at: nil, purpose: "user_data" })
    end
  end

  # need to make it generate something first
  # test "cluade download file" do
  #   VCR.use_cassette(vcr_cassette_name) do
  #     result = LlmGateway::Client.download_file("anthropic", file_id: "file_011CRub6FQG7ympTxXw81mic")
  #     assert_equal(result, { type: "file", id: "file_011CRub6FQG7ympTxXw81mic", size_bytes: 13, created_at: "2025-08-08T04:10:55.298000Z", filename: "test.txt", mime_type: "application/octet-stream", downloadable: false })
  #   end
  # end

  test "openai upload file" do
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.upload_file("openai", filename: "test.txt", content: "Hello, world!", mime_type: "text/plain")
      assert_equal(result, { id: "file-Kb6X7f8YDffu7FG1NcaPVu", size_bytes: 13, created_at: "2025-08-08T06:03:16.000000Z", filename: "test.txt", mime_type: nil, downloadable: false, expires_at: nil, purpose: "user_data" })
    end
  end

  # need to make it generate something first
  # test "open ai download file" do
  #   VCR.use_cassette(vcr_cassette_name) do
  #     result = LlmGateway::Client.download_file("openai", file_id: "file-Kb6X7f8YDffu7FG1NcaPVu")
  #     assert_equal(result, { type: "file", id: "file_011CRub6FQG7ympTxXw81mic", size_bytes: 13, created_at: "2025-08-08T04:10:55.298000Z", filename: "test.txt", mime_type: "application/octet-stream", downloadable: false })
  #   end
  # end


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
