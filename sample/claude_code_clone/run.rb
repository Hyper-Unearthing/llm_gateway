require 'tty-prompt'
require_relative '../../lib/llm_gateway'
require_relative 'claude_code_clone.rb'

# Terminal Runner for FileSearchBot
class FileSearchTerminalRunner
  def initialize
    @prompt = TTY::Prompt.new
  end

  def start
    puts "First, let's configure your LLM settings:\n\n"

    model, api_key = setup_configuration
    bot = ClaudeCloneClone.new(model, api_key)

    puts "Type 'quit' or 'exit' to stop.\n\n"

    loop do
      user_input = @prompt.ask("What can i do for you?")

      break if [ 'quit', 'exit' ].include?(user_input.downcase)

      bot.query(user_input)
    end
  end

  private

  def setup_configuration
    model = @prompt.ask("Enter model (default: claude-3-7-sonnet-20250219):") do |q|
      q.default 'claude-3-7-sonnet-20250219'
    end

    api_key = @prompt.mask("Enter your API key:") do |q|
      q.required true
    end

    [ model, api_key ]
  end
end

# Start the bot
if __FILE__ == $0
  runner = FileSearchTerminalRunner.new
  runner.start
end
