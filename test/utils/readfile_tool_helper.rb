# frozen_string_literal: true

require "base64"

module ReadfileToolHelper
  def readfile_tool
    {
      name: "readfile",
      description: "Reads a file and returns its contents",
      input_schema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to a file" }
        },
        required: [ "path" ]
      }
    }
  end

  def evaluate_readfile(input)
    path = input[:path] || input["path"]
    full_path = File.expand_path("../fixtures/red-circle.png", __dir__)

    raise "Unsupported path: #{path}" unless path == "test/fixtures/red-circle.png"

    image_data = Base64.strict_encode64(File.binread(full_path))
    [
      { type: "text", text: "Read image file [image/png]" },
      { type: "image", data: image_data, media_type: "image/png" }
    ]
  end
end
