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

### Sample Application

See the [file search bot example](sample/directory_bot/) for a complete working application that demonstrates:
- Creating reusable Prompt and Tool classes
- Handling conversation transcripts with tool execution
- Building an interactive terminal interface

To run the sample:

```bash
cd sample/directory_bot
ruby run.rb
```

The bot will prompt for your model and API key, then allow you to ask natural language questions about finding files and searching directories.

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
