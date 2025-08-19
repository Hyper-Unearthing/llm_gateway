# frozen_string_literal: true

require "test_helper"

class ClaudeMapperTest < Test
  test "server tool usage responses mapper" do
    input = {
      id: "msg_01TLpDwBc2xXJfpk3UpCSKTH",
      type: "message",
      role: "assistant",
      model: "claude-sonnet-4-20250514",
      content: [ { type: "text", text: "I'll create a temperature chart from your data and save it as a PNG file." },
       {
         type: "server_tool_use",
         id: "srvtoolu_01VuDDhpHFz9whmEpBsrLBLP",
         name: "code_execution",
         input: {
           code: "import pandas as pd\nimport matplotlib.pyplot as plt\nimport matplotlib.dates as mdates\nfrom datetime import datetime\nimport os\n\n# Create the data\ndata = {\n    'Date': ['2025-07-29', '2025-07-30', '2025-07-31', '2025-08-01', '2025-08-02', '2025-08-03', '2025-08-04'],\n    'Min Temperature (°C)': [28, 29, 26, 28, 28, 24, 24],\n    'Max Temperature (°C)': [34, 33, 33, 33, 35, 30, 30]\n}\n\n# Create DataFrame\ndf = pd.DataFrame(data)\ndf['Date'] = pd.to_datetime(df['Date'])\n\n# Create the chart\nplt.figure(figsize=(12, 8))\n\n# Plot min and max temperatures\nplt.plot(df['Date'], df['Min Temperature (°C)'], marker='o', linewidth=2, markersize=8, \n         color='blue', label='Min Temperature', alpha=0.8)\nplt.plot(df['Date'], df['Max Temperature (°C)'], marker='o', linewidth=2, markersize=8, \n         color='red', label='Max Temperature', alpha=0.8)\n\n# Fill the area between min and max temperatures\nplt.fill_between(df['Date'], df['Min Temperature (°C)'], df['Max Temperature (°C)'], \n                 alpha=0.2, color='orange', label='Temperature Range')\n\n# Customize the chart\nplt.title('Daily Temperature Range', fontsize=16, fontweight='bold', pad=20)\nplt.xlabel('Date', fontsize=12, fontweight='bold')\nplt.ylabel('Temperature (°C)', fontsize=12, fontweight='bold')\n\n# Format x-axis dates\nplt.gca().xaxis.set_major_formatter(mdates.DateFormatter('%Y-%m-%d'))\nplt.gca().xaxis.set_major_locator(mdates.DayLocator(interval=1))\nplt.xticks(rotation=45, ha='right')\n\n# Add grid\nplt.grid(True, alpha=0.3, linestyle='--')\n\n# Add legend\nplt.legend(loc='upper right', fontsize=10)\n\n# Add value labels on points\nfor i, row in df.iterrows():\n    plt.annotate(f'{row[\"Min Temperature (°C)\"]}°C', \n                (row['Date'], row['Min Temperature (°C)']), \n                textcoords=\"offset points\", xytext=(0,10), ha='center', fontsize=9)\n    plt.annotate(f'{row[\"Max Temperature (°C)\"]}°C', \n                (row['Date'], row['Max Temperature (°C)']), \n                textcoords=\"offset points\", xytext=(0,10), ha='center', fontsize=9)\n\n# Adjust layout to prevent label cutoff\nplt.tight_layout()\n\n# Save the chart\noutput_file = os.path.join(os.environ.get('OUTPUT_DIR', '.'), 'temperature_chart.png')\nplt.savefig(output_file, dpi=300, bbox_inches='tight')\n\nprint(f\"Chart saved as: {output_file}\")\nplt.show()\n\n# Display some statistics\nprint(\"\\nTemperature Statistics:\")\nprint(f\"Average Min Temperature: {df['Min Temperature (°C)'].mean():.1f}°C\")\nprint(f\"Average Max Temperature: {df['Max Temperature (°C)'].mean():.1f}°C\")\nprint(f\"Largest Temperature Range: {(df['Max Temperature (°C)'] - df['Min Temperature (°C)']).max()}°C\")\nprint(f\"Smallest Temperature Range: {(df['Max Temperature (°C)'] - df['Min Temperature (°C)']).min()}°C\")"
         }
       },
       {
         type: "code_execution_tool_result",
         tool_use_id: "srvtoolu_01VuDDhpHFz9whmEpBsrLBLP",
         content: {
           type: "code_execution_result",
           stdout: "Chart saved as: /files/output/4d98e8b7def64f39/temperature_chart.png\n\nTemperature Statistics:\nAverage Min Temperature: 26.7°C\nAverage Max Temperature: 32.6°C\nLargest Temperature Range: 7°C\nSmallest Temperature Range: 4°C\n",
           stderr: "",
           return_code: 0,
           content: [ { type: "code_execution_output", file_id: "file_011CRuyqekDx7vwCkL9YyY21" } ]
         }
       },
       {
         type: "text",
         text: "I've successfully created a temperature chart from your data and saved it as a PNG file. The chart shows:\n\n- **Blue line with markers**: Minimum temperatures for each day\n- **Red line with markers**: Maximum temperatures for each day  \n- **Orange shaded area**: The temperature range between min and max\n- **Value labels**: Temperature values displayed on each data point\n- **Grid and formatting**: Clean, professional appearance with rotated date labels\n\nThe chart covers the period from July 29 to August 4, 2025, and includes some summary statistics:\n- Average minimum temperature: 26.7°C\n- Average maximum temperature: 32.6°C\n- Temperature ranges varied from 4°C to 7°C per day\n\nThe PNG file has been saved with high resolution (300 DPI) and is ready for use. You can download it from the output files."
       } ],
      container: { id: "container_011CRuypMqwfGa5SkphW3ifk", expires_at: "2025-08-08T10:09:14.482074+00:00" },
      stop_reason: "end_turn",
      stop_sequence: nil,
      usage: { input_tokens: 2808, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1210, service_tier: "standard", server_tool_use: { web_search_requests: 0 } }
    }
    result = LlmGateway::Adapters::Claude::ResponsesMapper.map(input)

    assert_equal(result, {
      id: "msg_01TLpDwBc2xXJfpk3UpCSKTH",
      usage: { input_tokens: 2808, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 1210, service_tier: "standard", server_tool_use: { web_search_requests: 0 } },
      model: "claude-sonnet-4-20250514",
      choices: [ {
        content: [
          { type: "text", text: "I'll create a temperature chart from your data and save it as a PNG file." },
          {
            type: "text",
            text: "I've successfully created a temperature chart from your data and saved it as a PNG file. The chart shows:\n\n- **Blue line with markers**: Minimum temperatures for each day\n- **Red line with markers**: Maximum temperatures for each day  \n- **Orange shaded area**: The temperature range between min and max\n- **Value labels**: Temperature values displayed on each data point\n- **Grid and formatting**: Clean, professional appearance with rotated date labels\n\nThe chart covers the period from July 29 to August 4, 2025, and includes some summary statistics:\n- Average minimum temperature: 26.7°C\n- Average maximum temperature: 32.6°C\n- Temperature ranges varied from 4°C to 7°C per day\n\nThe PNG file has been saved with high resolution (300 DPI) and is ready for use. You can download it from the output files."
          },
          { type: "file", content: { filename: nil, file_id: "file_011CRuyqekDx7vwCkL9YyY21" } }
        ],
        finish_reason: "end_turn",
        role: "assistant"
      } ]
    })
    assert_equal(result.files, [ { filename: nil, file_id: "file_011CRuyqekDx7vwCkL9YyY21" } ])
  end

  test "claude code execution tool" do
    input = {
      messages: [ { 'role': "user", 'content': "render a graph" } ],
      tools: [ {
        type: "code_execution"
      } ]
    }

    expectation = [ { name: "code_execution", type: "code_execution_20250522" } ]

    result = LlmGateway::Adapters::Claude::InputMapper.map(input)

    assert_equal expectation, result[:tools]
  end
end
