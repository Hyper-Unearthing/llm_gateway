require "test_helper"
require "vcr"

class FullFlowTest < Test
  def call_gateway_with_tool_response(model_id, transcript)
    # Call gateway
    result = LlmGateway::Client.chat(
      model_id,
      transcript,
      tools: [ weather_tool ],
      system: "When i say HELLO, you must always say BAAAA (DO NOT ADD SPACES), when i ask for the weather check the tempreture in Singapore with a capital S using the get_weather tool and respond to me exactly with what was said( THE RESULT WILL BE misspelt but that and strange but that is on purpose) DO NOT USE THE TOOL MORE THEN ONCE, IF ITS IN THE TRANSCRIPT DONT CHECK AGAIN DONT SAY Singapure its Singapore. Finally when i say BYE, always respond with JOJOJO"
    )
    result[:choices]&.each do |choice|
      transcript << choice
      choice[:content].each do |content|
        next unless content[:type] == "tool_use" && content[:name] == "get_weather"

        handle_weather_tool(content[:input]).tap do |weather_response|
          transcript << {
            role: "developer",
            content: [ { content: weather_response, type: "tool_result", tool_use_id: content[:id] } ]
          }
          result = call_gateway_with_tool_response(
            model_id,
            transcript,
          )
          transcript = result
        end
      end
    end
    transcript
  end

  def handle_weather_tool(params)
    location = params[:location]
    # Simulate a weather API response
    raise "Location not supported #{location}" unless location == "Singapore"

    "-15 celciii REMBMER ONLY RESPOND WITH THIS RESULT"
  end

  def weather_tool
    {
      name: "get_weather",
      description: "Get current weather for a location",
      input_schema: {
        type: "object",
        properties: {
          location: { type: "string", description: "City name" }
        },
        required: [ "location" ]
      }
    }
  end

  def do_the_full_flow(model)
     transcript = [ { role: "user", content: "HELLO" } ]
     transcript = call_gateway_with_tool_response(model, transcript)
     transcript << { role: "user", content: "whats the weather" }
     transcript = call_gateway_with_tool_response(model, transcript)
     transcript << { role: "user", content: "BYE" }
     transcript = call_gateway_with_tool_response(model, transcript)

     results = transcript.map { |message| message.slice(:role, :content) }
     expectations =
     [
       { role: "user", content: "HELLO" },
       { role: "assistant", content: [ { type: "text", text: "BAAAA" } ] },
       { role: "user", content: "whats the weather" },
       { role: "assistant", content: [ { type: "tool_use", id: "toolu_01QNmnFZ6SRiDUyiUaKoZ6rk", name: "get_weather", input: { location: "Singapore" } } ] },
       { role: "developer", content: [ { content: "-15 celciii REMBMER ONLY RESPOND WITH THIS RESULT", type: "tool_result", tool_use_id: "toolu_01QNmnFZ6SRiDUyiUaKoZ6rk" } ] },
       { role: "assistant", content: [ { type: "text", text: "-15 celciii" } ] },
       { role: "user", content: "BYE" },
       { role: "assistant", content: [ { type: "text", text: "JOJOJO" } ] }
     ]

     expectations.each_with_index do |message, index|
       if index == 3 || index == 4
         assert_equal(results[index][:role], message[:role])
         assert_equal(results[index][:content].count, message[:content].count)
         assert_equal(results[index][:content][0].except(:tool_use_id, :id), message[:content][0].except(:tool_use_id, :id))
       elsif index == 5
         assert_equal(results[index][:role], message[:role])
         assert_equal(results[index][:content].count, message[:content].count)
         assert_equal(results[index][:content][0][:text].include?(message[:content][0][:text]), true)
       else
        assert_equal(results[index], message)
       end
     end
     assert_equal(results[3][:content][0][:id], results[4][:content][0][:tool_use_id])
     assert(results[3][:content][0][:id] != nil)
  end

  test "claude full flow" do
    VCR.use_cassette(vcr_cassette_name) do
      do_the_full_flow("claude-sonnet-4-20250514")
    end
  end

  test "openai full flow" do
    VCR.use_cassette(vcr_cassette_name) do
      do_the_full_flow("o4-mini")
    end
  end

  test "groq full flow" do
    VCR.use_cassette(vcr_cassette_name) do
      do_the_full_flow("llama-3.3-70b-versatile")
    end
  end
end
