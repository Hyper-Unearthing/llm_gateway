# frozen_string_literal: true

require "test_helper"

class OpenAIMapperTest < Test
  test "open ai input mapper tool usage" do
    input = {
      messages: [ { role: "user", content: "What's the weather in Singapore? reply in 10 words and no special characters" },
             { content: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] },
             { role: "developer", content: [ { content: "-15 celcius", type: "tool_result", tool_use_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ" } ] } ],
      response_format: { type: "text" },
      tools: [ { name: "get_weather", description: "Get current weather for a location", input_schema: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } } ],
      system: [ { role: "system", content: "Talk like a pirate" } ]
    }


    expectation ={
      system: [ { role: "developer", content: "Talk like a pirate" } ],
      response_format: { type: "text" },
      messages: [ { role: "user", content: [ { type: "text", text: "What's the weather in Singapore? reply in 10 words and no special characters" } ] },
       {
         role: "assistant",
         content: nil,
         tool_calls: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "function", function: { name: "get_weather", arguments: "{\"location\":\"Singapore\"}" } } ]
       },
       {
         role: "tool",
         tool_call_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ",
         content: "-15 celcius"
       } ],
      tools: [ {
        type: "function",
        function: { name: "get_weather", description: "Get current weather for a location", parameters: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } }
      } ]
    }
    result = LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper.map(input)
    assert_equal expectation, result
  end

  test "open ai responses output mapper" do
    input = {
      model: "gpt-5-2025-08-07",
      id: "resp_6895f8d4a06881919dd57eaa397cc2220e2461b3232f5782",
      usage: { input_tokens: 9152, input_tokens_details: { cached_tokens: 2344 }, output_tokens: 2463, output_tokens_details: { reasoning_tokens: 1600 }, total_tokens: 11615 },
      output: [ { id: "rs_6895f8d92f4881919679a7bafc02ad550e2461b3232f5782", type: "reasoning", summary: [] },
       {
         id: "ci_6895f90178c481918b88c7bc16b6a6840e2461b3232f5782",
         type: "code_interpreter_call",
         status: "completed",
         code: "# Create and save a line chart of daily min and max temperatures as a PNG\r\n\r\nimport pandas as pd\r\nimport matplotlib.pyplot as plt\r\nimport matplotlib.dates as mdates\r\nfrom io import StringIO\r\n\r\n# Input data\r\ncsv_data = \"\"\"Date,Min Temperature (°C),Max Temperature (°C)\r\n2025-07-29,28,34\r\n2025-07-30,29,33\r\n2025-07-31,26,33\r\n2025-08-01,28,33\r\n2025-08-02,28,35\r\n2025-08-03,24,30\r\n2025-08-04,24,30\r\n\"\"\"\r\n\r\n# Read into DataFrame\r\ndf = pd.read_csv(StringIO(csv_data), parse_dates=['Date']).sort_values('Date')\r\n\r\n# Plot\r\nplt.figure(figsize=(9, 4.8))\r\nplt.plot(df['Date'], df['Min Temperature (°C)'], marker='o', label='Min')\r\nplt.plot(df['Date'], df['Max Temperature (°C)'], marker='o', label='Max')\r\nplt.fill_between(df['Date'], df['Min Temperature (°C)'], df['Max Temperature (°C)'], color='tab:blue', alpha=0.1)\r\n\r\nplt.title('Daily Min and Max Temperatures')\r\nplt.xlabel('Date')\r\nplt.ylabel('Temperature (°C)')\r\nplt.grid(True, alpha=0.3)\r\nplt.legend()\r\n\r\n# Format dates on x-axis\r\nax = plt.gca()\r\nax.xaxis.set_major_locator(mdates.DayLocator())\r\nax.xaxis.set_major_formatter(mdates.DateFormatter('%b %d'))\r\nplt.xticks(rotation=45, ha='right')\r\n\r\nplt.tight_layout()\r\n\r\n# Save PNG\r\nout_path = '/mnt/data/daily_temperatures.png'\r\nplt.savefig(out_path, dpi=200)\r\nplt.show()\r\n\r\nout_path",
         container_id: "cntr_6895f8d71ce48191ad569ad0c53facc70364d351cca9ca25",
         outputs: nil
       },
       { id: "rs_6895f90ab8a88191a4fdfe7a373484310e2461b3232f5782", type: "reasoning", summary: [] },
       {
         id: "ci_6895f90fcc488191960aaad6aa489b540e2461b3232f5782",
         type: "code_interpreter_call",
         status: "completed",
         code: "# Re-run with robust handling for dates in fill_between\r\n\r\nimport pandas as pd\r\nimport matplotlib.pyplot as plt\r\nimport matplotlib.dates as mdates\r\nfrom io import StringIO\r\n\r\n# Input data\r\ncsv_data = \"\"\"Date,Min Temperature (°C),Max Temperature (°C)\r\n2025-07-29,28,34\r\n2025-07-30,29,33\r\n2025-07-31,26,33\r\n2025-08-01,28,33\r\n2025-08-02,28,35\r\n2025-08-03,24,30\r\n2025-08-04,24,30\r\n\"\"\"\r\n\r\n# Read into DataFrame\r\ndf = pd.read_csv(StringIO(csv_data), parse_dates=['Date']).sort_values('Date')\r\n\r\n# Prepare arrays for plotting\r\nx = mdates.date2num(df['Date'].dt.to_pydatetime())\r\ny_min = df['Min Temperature (°C)'].astype(float).values\r\ny_max = df['Max Temperature (°C)'].astype(float).values\r\n\r\n# Plot\r\nplt.figure(figsize=(9, 4.8))\r\nplt.plot(df['Date'], y_min, marker='o', label='Min')\r\nplt.plot(df['Date'], y_max, marker='o', label='Max')\r\nplt.fill_between(x, y_min, y_max, color='tab:blue', alpha=0.1)  # Use numeric dates for fill_between\r\n\r\nplt.title('Daily Min and Max Temperatures')\r\nplt.xlabel('Date')\r\nplt.ylabel('Temperature (°C)')\r\nplt.grid(True, alpha=0.3)\r\nplt.legend()\r\n\r\n# Format dates on x-axis\r\nax = plt.gca()\r\nax.xaxis.set_major_locator(mdates.DayLocator())\r\nax.xaxis.set_major_formatter(mdates.DateFormatter('%b %d'))\r\nplt.xticks(rotation=45, ha='right')\r\n\r\nplt.tight_layout()\r\n\r\n# Save PNG\r\nout_path = '/mnt/data/daily_temperatures.png'\r\nplt.savefig(out_path, dpi=200)\r\nplt.show()\r\n\r\nout_path",
         container_id: "cntr_6895f8d71ce48191ad569ad0c53facc70364d351cca9ca25",
         outputs: nil
       },
       {
         id: "msg_6895f9176cec819195830807242e07440e2461b3232f5782",
         type: "message",
         status: "completed",
         content: [ {
           type: "output_text",
           annotations: [ {
             type: "container_file_citation",
             container_id: "cntr_6895f8d71ce48191ad569ad0c53facc70364d351cca9ca25",
             end_index: 0,
             file_id: "cfile_6895f914da588191bed53ebbb5d24033",
             filename: "cfile_6895f914da588191bed53ebbb5d24033.png",
             start_index: 0
           } ],
           logprobs: [],
           text: "Your chart has been created and saved.\nDownload the PNG: sandbox:/mnt/data/daily_temperatures.png"
         } ],
         role: "assistant"
       } ]
    }

    result = LlmGateway::Adapters::OpenAi::Responses::OutputMapper.map(input)
    expected = {
      model: "gpt-5-2025-08-07",
      id: "resp_6895f8d4a06881919dd57eaa397cc2220e2461b3232f5782",
      usage: { input_tokens: 9152, input_tokens_details: { cached_tokens: 2344 }, output_tokens: 2463, output_tokens_details: { reasoning_tokens: 1600 }, total_tokens: 11615 },
      choices: [
        { id: "rs_6895f8d92f4881919679a7bafc02ad550e2461b3232f5782", role: nil, content: [ { type: "reasoning", summary: [] } ] },
        {
          id: "ci_6895f90178c481918b88c7bc16b6a6840e2461b3232f5782",
          role: nil,
          content: [ {
            type: "code_interpreter_call",
            status: "completed",
            code: "# Create and save a line chart of daily min and max temperatures as a PNG\r\n\r\nimport pandas as pd\r\nimport matplotlib.pyplot as plt\r\nimport matplotlib.dates as mdates\r\nfrom io import StringIO\r\n\r\n# Input data\r\ncsv_data = \"\"\"Date,Min Temperature (°C),Max Temperature (°C)\r\n2025-07-29,28,34\r\n2025-07-30,29,33\r\n2025-07-31,26,33\r\n2025-08-01,28,33\r\n2025-08-02,28,35\r\n2025-08-03,24,30\r\n2025-08-04,24,30\r\n\"\"\"\r\n\r\n# Read into DataFrame\r\ndf = pd.read_csv(StringIO(csv_data), parse_dates=['Date']).sort_values('Date')\r\n\r\n# Plot\r\nplt.figure(figsize=(9, 4.8))\r\nplt.plot(df['Date'], df['Min Temperature (°C)'], marker='o', label='Min')\r\nplt.plot(df['Date'], df['Max Temperature (°C)'], marker='o', label='Max')\r\nplt.fill_between(df['Date'], df['Min Temperature (°C)'], df['Max Temperature (°C)'], color='tab:blue', alpha=0.1)\r\n\r\nplt.title('Daily Min and Max Temperatures')\r\nplt.xlabel('Date')\r\nplt.ylabel('Temperature (°C)')\r\nplt.grid(True, alpha=0.3)\r\nplt.legend()\r\n\r\n# Format dates on x-axis\r\nax = plt.gca()\r\nax.xaxis.set_major_locator(mdates.DayLocator())\r\nax.xaxis.set_major_formatter(mdates.DateFormatter('%b %d'))\r\nplt.xticks(rotation=45, ha='right')\r\n\r\nplt.tight_layout()\r\n\r\n# Save PNG\r\nout_path = '/mnt/data/daily_temperatures.png'\r\nplt.savefig(out_path, dpi=200)\r\nplt.show()\r\n\r\nout_path",
            container_id: "cntr_6895f8d71ce48191ad569ad0c53facc70364d351cca9ca25",
            outputs: nil
          } ]
        },
        { id: "rs_6895f90ab8a88191a4fdfe7a373484310e2461b3232f5782", role: nil, content: [ { type: "reasoning", summary: [] } ] },
        {
          id: "ci_6895f90fcc488191960aaad6aa489b540e2461b3232f5782",
          role: nil,
          content: [ {
            type: "code_interpreter_call",
            status: "completed",
            code: "# Re-run with robust handling for dates in fill_between\r\n\r\nimport pandas as pd\r\nimport matplotlib.pyplot as plt\r\nimport matplotlib.dates as mdates\r\nfrom io import StringIO\r\n\r\n# Input data\r\ncsv_data = \"\"\"Date,Min Temperature (°C),Max Temperature (°C)\r\n2025-07-29,28,34\r\n2025-07-30,29,33\r\n2025-07-31,26,33\r\n2025-08-01,28,33\r\n2025-08-02,28,35\r\n2025-08-03,24,30\r\n2025-08-04,24,30\r\n\"\"\"\r\n\r\n# Read into DataFrame\r\ndf = pd.read_csv(StringIO(csv_data), parse_dates=['Date']).sort_values('Date')\r\n\r\n# Prepare arrays for plotting\r\nx = mdates.date2num(df['Date'].dt.to_pydatetime())\r\ny_min = df['Min Temperature (°C)'].astype(float).values\r\ny_max = df['Max Temperature (°C)'].astype(float).values\r\n\r\n# Plot\r\nplt.figure(figsize=(9, 4.8))\r\nplt.plot(df['Date'], y_min, marker='o', label='Min')\r\nplt.plot(df['Date'], y_max, marker='o', label='Max')\r\nplt.fill_between(x, y_min, y_max, color='tab:blue', alpha=0.1)  # Use numeric dates for fill_between\r\n\r\nplt.title('Daily Min and Max Temperatures')\r\nplt.xlabel('Date')\r\nplt.ylabel('Temperature (°C)')\r\nplt.grid(True, alpha=0.3)\r\nplt.legend()\r\n\r\n# Format dates on x-axis\r\nax = plt.gca()\r\nax.xaxis.set_major_locator(mdates.DayLocator())\r\nax.xaxis.set_major_formatter(mdates.DateFormatter('%b %d'))\r\nplt.xticks(rotation=45, ha='right')\r\n\r\nplt.tight_layout()\r\n\r\n# Save PNG\r\nout_path = '/mnt/data/daily_temperatures.png'\r\nplt.savefig(out_path, dpi=200)\r\nplt.show()\r\n\r\nout_path",
            container_id: "cntr_6895f8d71ce48191ad569ad0c53facc70364d351cca9ca25",
            outputs: nil
          } ]
        },
        { id: "msg_6895f9176cec819195830807242e07440e2461b3232f5782", role: "assistant", content: [ { type: "text", text: "Your chart has been created and saved.\nDownload the PNG: sandbox:/mnt/data/daily_temperatures.png" } ] }
      ]
    }
    assert_equal(result, expected)
  end

  test "open ai input mapper tool usage, with role assistant " do
    input = {
      messages: [ { role: "user", content: "What's the weather in Singapore? reply in 10 words and no special characters" },
             { role: "assistant", content: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "tool_use", name: "get_weather", input: { location: "Singapore" } } ] },
             { role: "developer", content: [ { content: "-15 celcius", type: "tool_result", tool_use_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ" } ] } ],
      response_format: { type: "text" },
      tools: [ { name: "get_weather", description: "Get current weather for a location", input_schema: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } } ],
      system: [ { role: "system", content: "Talk like a pirate" } ]
    }


    expectation ={
      system: [ { role: "developer", content: "Talk like a pirate" } ],
      response_format: { type: "text" },
      messages: [ { role: "user", content: [ { type: "text", text: "What's the weather in Singapore? reply in 10 words and no special characters" } ] },
       {
         role: "assistant",
         content: nil,
         tool_calls: [ { id: "call_gpXfy9l9QNmShNEbNI1FyuUZ", type: "function", function: { name: "get_weather", arguments: "{\"location\":\"Singapore\"}" } } ]
       },
       {
         role: "tool",
         tool_call_id: "call_gpXfy9l9QNmShNEbNI1FyuUZ",
         content: "-15 celcius"
       } ],
      tools: [ {
        type: "function",
        function: { name: "get_weather", description: "Get current weather for a location", parameters: { type: "object", properties: { location: { type: "string", description: "City name" } }, required: [ "location" ] } }
      } ]
    }
    result = LlmGateway::Adapters::OpenAi::ChatCompletions::InputMapper.map(input)

    assert_equal expectation, result
  end
end
