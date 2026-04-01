# frozen_string_literal: true

require "test_helper"
require "json"
require_relative "../../lib/llm_gateway/adapters/claude/stream_mapper"
require_relative "../../lib/llm_gateway/adapters/stream_accumulator"

ANTHROPIC_STREAM_TEXT_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/anthropic_stream/text_events.json", __dir__)), symbolize_names: true)
ANTHROPIC_STREAM_TOOL_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/anthropic_stream/tool_events.json", __dir__)), symbolize_names: true)
ANTHROPIC_STREAM_THINKING_EVENTS_FIXTURE = JSON.parse(File.read(File.expand_path("../fixtures/anthropic_stream/thinking_events.json", __dir__)), symbolize_names: true)

class StreamTest < Test
  test "test chunk mapping text only" do
    mapper = LlmGateway::Adapters::Claude::StreamMapper.new

    accumulator = StreamAccumulator.new
    ANTHROPIC_STREAM_TEXT_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end
    expectation = {
      id: "msg_01YBuXt8Jmgduug8z1Apqu9f",
      model: "claude-sonnet-4-20250514",
      role: "assistant",
      stop_reason: "stop",
      stop_sequence: nil,
      usage: { input_tokens: 34, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 7, reasoning_tokens: 0 },
      content: [ { type: "text", text: "Hello test successful" } ]
    }
    assert_equal(expectation, accumulator.result)
  end

  test "test chunk mapping text and tools" do
    mapper = LlmGateway::Adapters::Claude::StreamMapper.new

    accumulator = StreamAccumulator.new
    ANTHROPIC_STREAM_TOOL_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end
    expectation = {
      id: "msg_019UkgUmCHQymKMRohqk5C2d",
      model: "claude-sonnet-4-20250514",
      role: "assistant",
      stop_reason: "tool_use",
      stop_sequence: nil,
      usage: { input_tokens: 914, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 115, reasoning_tokens: 0 },
      content: [
        { type: "text", text: "I'll calculate 15 + 27 for you using the math_operation tool." },
        { type: "tool_use", id: "toolu_01QTN9kuNWuCQuGA7NQqzTv7", name: "math_operation", input: { a: 15, b: 27, operation: "add" } }
      ]
    }
    assert_equal(expectation, accumulator.result)
  end

  test "test chunk mapping text and thinking" do
    mapper = LlmGateway::Adapters::Claude::StreamMapper.new

    accumulator = StreamAccumulator.new
    ANTHROPIC_STREAM_THINKING_EVENTS_FIXTURE.each do |chunk|
      accumulator.push(mapper.map(chunk))
    end
    expectation = {
      id: "msg_01XAGXXkhCPRfdQu2ynxVEHX",
      model: "claude-sonnet-4-20250514",
      role: "assistant",
      stop_reason: "stop",
      stop_sequence: nil,
      usage: { input_tokens: 96, cache_creation_input_tokens: 0, cache_read_input_tokens: 0, output_tokens: 617, reasoning_tokens: 0 },
      content: [ { type: "reasoning", reasoning: "The human is asking me to think about \"44 + 27s\". This could mean a few different things:\n\n1. They might mean 44 + 27 * s, where s is a variable\n2. They might mean 44 + 27 seconds (if \"s\" stands for seconds)\n3. They might have meant 44 + 27 = 71\n4. They might be asking about some other interpretation\n\nLet me consider the most likely interpretations:\n\nIf it's 44 + 27s as an algebraic expression:\n- This would be 44 + 27s, which can't be simplified further without knowing the value of s\n- If s = 0, then 44 + 27(0) = 44\n- If s = 1, then 44 + 27(1) = 71\n- If s = 2, then 44 + 27(2) = 44 + 54 = 98\n- And so on...\n\nIf they meant just 44 + 27:\n44 + 27 = 71\n\nThe phrase \"think long and hard\" suggests they want me to consider this deeply or from multiple angles. Let me think about what might be interesting or significant about this expression or these numbers.", signature: "Ev0HCkYICxgCKkALBEsTWS01TWfwl8jeekEf33OFyyj1dUvT8uh67MGacarqEBhVa+YDdomZO3Xn007LQ+rAjtm2j/TEnZAxuh+sEgxPTshSDGqqPB4QnbQaDB87W7bXDwrrUOcs2iIwcSApDB/0kGcu6oBaMnDK8flYHJt9OiaxRc0JgnEe6kR8NwrHHpAmU01/2kHa5paBKuQGazRvoI2DeC3nscQ2x6mIiKUt9rWxY4nle/yYDCdlDkPGbv1OG7915xJCct/A+Nx6YSyVA8bDMKzy8YQYW0o1eWm7mrzJ6GuJsPhrWzOR4IkCdG/+KPC0o1a8DBNwQ0OvijvRqMGWdTsFk4TmUXLzRkgN88Y4AoFXPDj7rkIlWj6+efleoS9Slv/1QtxarVFelgLSJoS9W8kZPTLh27hCXRFVezlHC5TaZBJDqBlHwsxr6AdVqsyh6jBiD9pbxlCMmeJchvmqJ4ndxVGgHoSmfCMlNjOa//+3fnrWgCXQJpkuFCKPDDwILZSUj8X9zcC6V5GwVHisCelWkWk+6lGTyJktRJYrUTMu4lwB8FEJS2jctmWXZW0+xqsP0zbCEdkz34nLA1h/qN7QaUwmIM3BF+wGLoUQT1Ms4tr+ePU9V5jkOaWzSUcJPzm3RAvetbFZeZRbj6dxms34cAYzZFUUf3CkEyaHxQn70nyHUEiTsU+bArW7w0aXgsD6KMNyA5pg3NVyv/n8LTXVPEzBo6wI8VN5/jJZnmcruLPkeRo7k437Vyy/lwwRRrux2HT3Ct1XLpDhZLteYNdFglMFeSfBp7pjnU6M/+Xmcu7LSjuOiNo/tCss4H8g8USsdsvFa3DgTt6WkmMRBWYHEGZDIOWP6Ne7hRR4qRL6UzqePOdwtUlYqtn4+/HXOKCxm3WIxU/i2qW4Q2zXPqeK7QmmZonu8UCGIwYwLPDYn4A/gb1MEgvBxcnbeq+I1aLZfOmgjvEWLs3wrbkWB8WKYp6yB5bfYbms0J6c44H/iFhOR/5ZLT2ojAi26LNBFDIRwel4XS+TcSs5jr/ND1dWYj+hSlITrxxkYPl6yA0TLKR9lPiAu0xqDnU6iEiHjRvX7VI13xmOuDCe+QIQvDxgYiIsBC+bXt5Bh7f4rgOadnBE6DyEmrAwqJOqFW8G8kJooyc63jRyE1FyI5Q3vVb20qclWzx1ez9YLgV4nVjMg61RLFqwdkjhYyJT4lGAqqrzvAx5PCku0QBrShhK+m2unyYNRpRtKp/2olqOM6WqmRdKswR7IHukysmQA2z3Xh1QI4Jemrfj6qMGdnvIVCwLTERbF/vaPVTAYrwCMbf7VXK98eE+5zIg+Nl48sHtW0EiE/rVORRuhYZX9RgB" }, { type: "text", text: "Looking at \"44 + 27s\", I can interpret this in several ways:\n\n**As an algebraic expression:**\n- This represents a linear function: f(s) = 44 + 27s\n- The slope is 27, meaning for each unit increase in s, the value increases by 27\n- When s = 0, the value is 44 (the y-intercept)\n- When s = 1, we get 44 + 27 = 71\n- When s = 2, we get 44 + 54 = 98\n\n**If you meant 44 + 27 = 71:**\n- These are interesting numbers: 44 is 4×11, 27 is 3³, and 71 is prime\n- 71 is actually the largest two-digit prime whose digits are also prime\n\n**Pattern considerations:**\n- 44 has repeated digits\n- 27 = 3³ (perfect cube)\n- The digits 4, 4, 2, 7 sum to 17\n- 71 reversed is 17\n\n**If \"s\" represents seconds or another unit:**\n- This could be a time calculation or rate problem\n- 44 base units plus 27 units per second (or other rate)\n\nWhat specific aspect of this expression were you hoping I'd explore? The mathematical properties, a particular application, or something else entirely?" } ]
    }
    assert_equal(expectation, accumulator.result)
  end
end
