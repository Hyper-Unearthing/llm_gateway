# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "open3"
require "rbconfig"

class GenerateModelCatalogTest < Test
  test "generates Cloudflare catalog entries with canonical upstream IDs and routing prefixes" do
    source = {
      "anthropic" => { "models" => {} },
      "openai" => { "models" => { "unchanged-alias" => { "canonical_model_id" => "openai/not-the-alias" } } },
      "groq" => { "models" => {} },
      "cloudflare-ai-gateway" => {
        "models" => {
          "anthropic/claude-haiku-5.5" => {
            "canonical_model_id" => "anthropic/claude-haiku-5-5",
            "name" => "Claude Haiku 5.5",
            "limit" => { "context" => 1_000_000, "output" => 128_000 },
            "cost" => { "input" => 0.1, "output" => 0.5 },
            "modalities" => { "input" => [ "text" ], "output" => [ "text" ] },
            "tool_call" => true
          },
          "google/gemini-2.5-flash" => {},
          "xai/grok-4.7" => {},
          "minimax/m3.1-flash" => { "canonical_model_id" => "minimax/MiniMax-M3.1-Flash" }
        }
      }
    }

    Dir.mktmpdir("gateway-catalog") do |root|
      FileUtils.mkdir_p(File.join(root, "scripts"))
      FileUtils.mkdir_p(File.join(root, "lib/llm_gateway/models"))
      script = File.join(root, "scripts/generate_model_catalog.rb")
      FileUtils.cp(File.expand_path("../../scripts/generate_model_catalog.rb", __dir__), script)
      input = File.join(root, "source.json")
      File.write(input, JSON.generate(source))
      stdout, stderr, status = Open3.capture3(RbConfig.ruby, script, input)
      assert status.success?, "#{stdout}\n#{stderr}"
      definitions = JSON.parse(File.read(File.join(root, "lib/llm_gateway/models/generated.json"))).fetch("definitions")
      cloudflare = definitions.select { |entry| entry["provider"] == "cloudflare-ai-gateway" }
      assert_equal %w[anthropic/claude-haiku-5-5 google-ai-studio/gemini-2.5-flash grok/grok-4.7 minimax/MiniMax-M3.1-Flash], cloudflare.map { |entry| entry["id"] }
      haiku = cloudflare.first
      assert_equal "Claude Haiku 5.5", haiku["name"]
      assert_equal "models_dev", haiku["source"]
      assert_equal 1_000_000, haiku["context_window"]
      assert_equal true, haiku.dig("capabilities", "tool_calling")
      assert_equal "0.1", haiku.dig("pricing", "input")
      assert_equal "unchanged-alias", definitions.find { |entry| entry["provider"] == "openai" }.fetch("id")
    end
  end
end
