# frozen_string_literal: true

require "test_helper"

class InputDocumentMapperTest < Test
  test "claude input document mapping" do
    input = { messages: [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "file", data: "abc\n", media_type: "text/plain", name: "small.txt"  } ] } ] }
    output = [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "document", source: { media_type: "text/plain", type: "text", data: "abc\n" } } ] } ]
    result = LlmGateway::Adapters::Claude::InputMapper.map(input)
    assert_equal output, result[:messages]
    end

  test "openai input document mapping" do
    input = { messages: [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "file", data: "abc\n", media_type: "text/plain", name: "small.txt" } ] } ] }
    output = [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "file", file: { filename: "small.txt", file_data: "data:application/pdf;base64,#{Base64.encode64("abc\n")}" } } ] } ]
    result = LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper.map(input)

    assert_equal output, result[:messages]
    end
end




# message = [ { role: "user", content: [ { type: "text", text: "return the content of the document exactly" }, { type: "document", source: { media_type: "text/plain", type: "text", data: "abc\n" } } ] } ]
