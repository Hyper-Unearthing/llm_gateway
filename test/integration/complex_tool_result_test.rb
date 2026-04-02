# frozen_string_literal: true

require "test_helper"
require "json"
require "base64"

class ComplexToolResultTest < Test
  def teardown
    LlmGateway.reset_configuration!
  end

  def load_provider(name)
    providers_path = File.expand_path("../fixtures/providers.json", __dir__)
    skip("Skipped: missing providers fixture at #{providers_path}") unless File.exist?(providers_path)

    providers = JSON.parse(File.read(providers_path))
    provider = providers.find { |entry| entry["name"] == name }
    skip("Skipped: provider not found in providers.json: #{name}") unless provider

    config = provider.fetch("config").dup
    key_env = config.delete("key_env")
    config["key"] = ENV.fetch(key_env) if key_env

    LlmGateway.configure([
      {
        "name" => provider.fetch("name"),
        "config" => config
      }
    ])

    LlmGateway.public_send(name)
  end

  def skip_on_authentication_error
    yield
  rescue LlmGateway::Errors::AuthenticationError => e
    skip("Skipped due to authentication error: #{e.message}")
  end

  def read_image_tool
    {
      name: "read_image",
      description: "Reads an image file and returns it for multimodal understanding",
      input_schema: {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to image file" }
        },
        required: [ "path" ]
      }
    }
  end

  def image_tool_result_flow_test(adapter)
    image_path = File.expand_path("../fixtures/red-circle.png", __dir__)
    image_data = Base64.strict_encode64(File.binread(image_path))

    transcript = [
      {
        role: "user",
        content: "Use read_image with path test/fixtures/red-circle.png, then explain exactly what is in the image."
      }
    ]

    first_response = adapter.stream(transcript, tools: [ read_image_tool ])
    transcript << first_response.to_h

    tool_call = first_response.content.find { |block| block.type == "tool_use" }
    refute_nil tool_call
    assert_equal "read_image", tool_call.name

    transcript << {
      role: "developer",
      content: [
        {
          type: "tool_result",
          tool_use_id: tool_call.id,
          content: [
            { type: "text", text: "Read image file [image/png]" },
            { type: "image", data: image_data, media_type: "image/png" }
          ]
        }
      ]
    }

    final_response = adapter.stream(transcript, tools: [ read_image_tool ])

    assert_equal "assistant", final_response.role
    assert_operator final_response.usage[:input_tokens], :>, 0
    assert_operator final_response.usage[:output_tokens], :>, 0
    assert_nil final_response.error_message

    text_content = final_response.content.find { |block| block.type == "text" }
    refute_nil text_content

    lower_content = text_content.text.downcase
    assert_includes lower_content, "red"
    assert_includes lower_content, "circle"
  end

  def self.provider_names
    providers_path = File.expand_path("../fixtures/providers.json", __dir__)
    return [] unless File.exist?(providers_path)

    JSON.parse(File.read(providers_path)).map { |entry| entry["name"] }
  end

  self.provider_names.each do |provider|
    test "#{provider} complex image tool_result" do
      skip_on_authentication_error do
        without_vcr do
          adapter = load_provider(provider)
          image_tool_result_flow_test(adapter)
        end
      end
    end
  end
end
