# LlmGateway

Provide nuts and bolts for LLM APIs. The goal is to provide a unified interface for multiple LLM provider API's; And Enable developers to have as much control as they want.

You can use the clients directly, Or you can use the gateway to have interop between clients.

## Supported Providers
Anthropic, OpenAi, Groq


## Installation

Add the gem to your application's Gemfile:

```bash
bundle add llm_gateway
```

Or install it yourself:

```bash
gem install llm_gateway
```

## Usage

### Basic Chat

```ruby
require 'llm_gateway'

# Simple text completion
result = LlmGateway::Client.chat(
  'claude-sonnet-4-20250514',
  'What is the capital of France?'
)

# With system message
result = LlmGateway::Client.chat(
  'gpt-4',
  'What is the capital of France?',
  system: 'You are a helpful geography teacher.'
)
```

### Prompt Class

You can also create reusable prompt classes by subclassing `LlmGateway::Prompt`:

```ruby
# Simple text completion with prompt class
class GeographyQuestionPrompt < LlmGateway::Prompt
  def initialize(model, question)
    super(model)
    @question = question
  end

  def prompt
    @question
  end
end

# Usage
geography_prompt = GeographyQuestionPrompt.new('claude-sonnet-4-20250514', 'What is the capital of France?')
result = geography_prompt.run

# With system message
class GeographyTeacherPrompt < LlmGateway::Prompt
  def initialize(model, question)
    super(model)
    @question = question
  end

  def prompt
    @question
  end

  def system_prompt
    'You are a helpful geography teacher.'
  end
end

# Usage
teacher_prompt = GeographyTeacherPrompt.new('gpt-4', 'What is the capital of France?')
result = teacher_prompt.run
```

### Using Prompt with Tools

You can combine the Prompt class with tools for more complex interactions:

```ruby
# Define a tool class
class GetWeatherTool < LlmGateway::Tool
  name 'get_weather'
  description 'Get current weather for a location'
  input_schema({
    type: 'object',
    properties: {
      location: { type: 'string', description: 'City name' }
    },
    required: ['location']
  })

  def execute(input, login = nil)
    # Your weather API implementation here
    "The weather in #{input['location']} is sunny and 25°C"
  end
end

class WeatherAssistantPrompt < LlmGateway::Prompt
  def initialize(model, location)
    super(model)
    @location = location
  end

  def prompt
    "What's the weather like in #{@location}?"
  end

  def system_prompt
    'You are a helpful weather assistant.'
  end

  def tools
    [GetWeatherTool]
  end
end

# Usage
weather_prompt = WeatherAssistantPrompt.new('claude-sonnet-4-20250514', 'Singapore')
result = weather_prompt.run
```

### Tool Usage (Function Calling)

```ruby
# Define a tool class
class GetWeatherTool < LlmGateway::Tool
  name 'get_weather'
  description 'Get current weather for a location'
  input_schema({
    type: 'object',
    properties: {
      location: { type: 'string', description: 'City name' }
    },
    required: ['location']
  })

  def execute(input, login = nil)
    # Your weather API implementation here
    "The weather in #{input['location']} is sunny and 25°C"
  end
end

# Use the tool
weather_tool = {
  name: 'get_weather',
  description: 'Get current weather for a location',
  input_schema: {
    type: 'object',
    properties: {
      location: { type: 'string', description: 'City name' }
    },
    required: ['location']
  }
}

result = LlmGateway::Client.chat(
  'claude-sonnet-4-20250514',
  'What\'s the weather in Singapore?',
  tools: [weather_tool],
  system: 'You are a helpful weather assistant.'
)

# Note: Tools are not automatically executed. The LLM will indicate when a tool should be called,
# but it's up to you to find the appropriate tool and execute it based on the response.

# Example of handling tool execution with conversation transcript:
class WeatherAssistant
  def initialize
    @transcript = []
    @weather_tool = {
      name: 'get_weather',
      description: 'Get current weather for a location',
      input_schema: {
        type: 'object',
        properties: {
          location: { type: 'string', description: 'City name' }
        },
        required: ['location']
      }
    }
  end

  attr_reader :weather_tool

  def process_message(content)
    # Add user message to transcript
    @transcript << { role: 'user', content: [{ type: 'text', text: content }] }

    result = LlmGateway::Client.chat(
      'claude-sonnet-4-20250514',
      @transcript,
      tools: [@weather_tool],
      system: 'You are a helpful weather assistant.'
    )

    process_response(result[:choices][0][:content])
  end

  private

  def process_response(response)
    # Add assistant response to transcript
    @transcript << { role: 'assistant', content: response }

    response.each do |message|
      if message[:type] == 'text'
        puts message[:text]
      elsif message[:type] == 'tool_use'
        result = handle_tool_use(message)

        # Add tool result to transcript
        tool_result = {
          type: 'tool_result',
          tool_use_id: message[:id],
          content: result
        }
        @transcript << { role: 'user', content: [tool_result] }

        # Continue conversation with full transcript context
        follow_up = LlmGateway::Client.chat(
          'claude-sonnet-4-20250514',
          @transcript,
          tools: [@weather_tool],
          system: 'You are a helpful weather assistant.'
        )

        process_response(follow_up[:choices][0][:content])
      end
    end
  end

  def handle_tool_use(message)
    tool_class = WeatherAssistantPrompt.find_tool(message[:name])
    raise "Unknown tool: #{message[:name]}" unless tool_class

    # Execute the tool with the provided input
    tool_instance = tool_class.new
    tool_instance.execute(message[:input])
  rescue StandardError => e
    "Error executing tool: #{e.message}"
  end
end

# Usage
assistant = WeatherAssistant.new
assistant.process_message("What's the weather in Singapore?")
```

### Response Format

All providers return responses in a consistent format:

```ruby
{
  choices: [
    {
      content: [
        { type: 'text', text: 'The capital of France is Paris.' }
      ],
      finish_reason: 'end_turn',
      role: 'assistant'
    }
  ],
  usage: {
    input_tokens: 15,
    output_tokens: 8,
    total_tokens: 23
  },
  model: 'claude-sonnet-4-20250514',
  id: 'msg_abc123'
}
```

### Error Handling

LlmGateway provides consistent error handling across all providers:

```ruby
begin
  result = LlmGateway::Client.chat('invalid-model', 'Hello')
rescue LlmGateway::Errors::UnsupportedModel => e
  puts "Unsupported model: #{e.message}"
rescue LlmGateway::Errors::AuthenticationError => e
  puts "Authentication failed: #{e.message}"
rescue LlmGateway::Errors::RateLimitError => e
  puts "Rate limit exceeded: #{e.message}"
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/Hyper-Unearthing/llm_gateway. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/Hyper-Unearthing/llm_gateway/blob/master/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the LlmGateway project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/Hyper-Unearthing/llm_gateway/blob/master/CODE_OF_CONDUCT.md).
