require 'dotenv/load'
require_relative 'simple_chat'
require 'debug'
class SimpleChatRunner
  def start
    puts "Welcome to Simple Chat!"
    puts "A two-panel TUI for chatting with AI models\n\n"

    model, api_key = load_configuration

    puts "Starting Simple Chat TUI with #{model}..."
    puts "Press 'q' to quit, Tab to change models\n\n"

    sleep(1)

    chat = SimpleChat.new(model, api_key)
    chat.start

    puts "Thanks for using Simple Chat!"
  end

  private

  def load_configuration
    model = ENV['DEFAULT_MODEL'] || 'claude-opus-4-20250514'

    api_key = if model.include?('claude')
      ENV['ANTHROPIC_API_KEY']
    elsif model.include?('llama') || model.include?('meta-llama') || model.include?('openai/gpt-oss')
      ENV['GROQ_API_KEY']
    else
      ENV['OPENAI_API_KEY']
    end

    unless api_key
      key_name = if model.include?('claude')
        'ANTHROPIC_API_KEY'
      elsif model.include?('llama') || model.include?('meta-llama') || model.include?('openai/gpt-oss')
        'GROQ_API_KEY'
      else
        'OPENAI_API_KEY'
      end

      puts "Error: API key not found in .env file"
      puts "Please set #{key_name} in your .env file"
      exit 1
    end

    [ model, api_key ]
  end
end

if __FILE__ == $0
  runner = SimpleChatRunner.new
  runner.start
end
