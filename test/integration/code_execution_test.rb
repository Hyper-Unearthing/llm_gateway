# frozen_string_literal: true

require "test_helper"

class CodeExecutionTest < Test
  SINGAPORE_TEMPERATURES_CSV = <<~CSV
    Date,Min Temperature (°C),Max Temperature (°C)
    2025-07-29,28,34
    2025-07-30,29,33
    2025-07-31,26,33
    2025-08-01,28,33
    2025-08-02,28,35
    2025-08-03,24,30
    2025-08-04,24,30
  CSV

  test "claude code execution too" do
    query = [ { 'role': "user", 'content': "render a chart of temperatures per day #{SINGAPORE_TEMPERATURES_CSV} please save and return the png" } ]
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses("claude-sonnet-4-20250514", query, tools: [ {
        type: "code_execution"
      } ])
      file = LlmGateway::Client.download_file("anthropic", **result.files[0])
      assert_equal result,
        {
          id: "msg_01RZapBGommCtPA6WwbYEqDy",
          usage: { input_tokens: 2739, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1044, service_tier: "standard", server_tool_use: { web_search_requests: 0 } },
          model: "claude-sonnet-4-20250514",
          choices: [ {
            content: [ { type: "text", text: "I'll create a temperature chart from your data and save it as a PNG file." },
                          {
                            type: "text",
                            text: "I've created a comprehensive temperature chart from your data and saved it as a PNG file. The chart includes:\n\n- **Blue line with circles**: Minimum temperatures\n- **Red line with squares**: Maximum temperatures  \n- **Light blue shaded area**: Temperature range between min and max\n- **Temperature values**: Displayed on each data point\n- **Formatted dates**: On the x-axis\n- **Grid lines**: For easier reading\n\nThe chart clearly shows the temperature variations over the week from July 29 to August 4, 2025, with temperatures ranging from a low of 24°C to a high of 35°C. The PNG file has been saved with high quality (300 DPI) and is ready for use."
                          }, { type: "file", content: { filename: nil, file_id: "file_011CRwsZ5CUKG34w1Re2wQYq" } } ],
            finish_reason: "end_turn",
            role: "assistant"
          } ]
        }
      assert_equal file.size, 243488
      assert_equal result.files,  [ { filename: nil, file_id: "file_011CRwsZ5CUKG34w1Re2wQYq" } ]
    end
  end

  test "openai code execution too" do
    query = [ { 'role': "user", 'content': "render a chart of temperatures per day #{SINGAPORE_TEMPERATURES_CSV} please save and return the png" } ]
    VCR.use_cassette(vcr_cassette_name) do
      result = LlmGateway::Client.responses("gpt-5", query, tools: [ {
        type: "code_execution"
      } ])
      file = LlmGateway::Client.download_file("openai", **result.files[0])
      assert_equal result,
        {
          choices: [ {
            content: [
                        { type: "text", text: "Your chart has been created and saved as a PNG.\n\nDownload the PNG: sandbox:/mnt/data/temperatures_per_day.png" },
                        { type: "file", content: { file_id: "cfile_68970e806b9081918f0a09d6a57721c8", filename: "cfile_68970e806b9081918f0a09d6a57721c8.png", container_id: "cntr_68970e5dd144819190d09a90455735dd049b7d4065343f21" } } ]
          } ],
          model: "gpt-5-2025-08-07",
          id: "resp_68970e5bc3c4819cbf1bc9a3729e2e3905dbc72471e3ec63",
          usage: { input_tokens: 8997, input_tokens_details: { cached_tokens: 5968 }, output_tokens: 2182, output_tokens_details: { reasoning_tokens: 1280 }, total_tokens: 11179 }
        }
      assert_equal file.size, 91814
      assert_equal result.files,  [ { file_id: "cfile_68970e806b9081918f0a09d6a57721c8", filename: "cfile_68970e806b9081918f0a09d6a57721c8.png", container_id: "cntr_68970e5dd144819190d09a90455735dd049b7d4065343f21" } ]
    end
  end
end
