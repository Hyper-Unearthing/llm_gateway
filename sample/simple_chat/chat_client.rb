require 'dotenv/load'
require_relative '../../lib/llm_gateway'

class ChatClient
  attr_accessor :model

  def initialize(model, api_key)
    @model = model
    @api_key = api_key
    @conversation_history = []
  end

  def model=(new_model)
    @model = new_model
    @api_key = get_api_key_for_model(new_model)
  end

  def send_message(message)
    @conversation_history << {
      role: 'user',
      content: [ { type: 'text', text: message } ]
    }


    begin
      response = LlmGateway::Client.chat(@model, @conversation_history, api_key: @api_key)

      if response && response[:choices] && response[:choices][0] && response[:choices][0][:content]
        assistant_content = response[:choices][0][:content]

        if assistant_content.is_a?(Array) && assistant_content[0] && assistant_content[0][:text]
          assistant_text = assistant_content[0][:text]
        elsif assistant_content.is_a?(String)
          assistant_text = assistant_content
        else
          assistant_text = "No response received"
        end

        @conversation_history << {
          role: 'assistant',
          content: [ { type: 'text', text: assistant_text } ]
        }

        assistant_text
      else
        "No response received from the model"
      end
    rescue => e
      raise "Failed to get response: #{e.message}"
    end
  end

  def clear_history
    @conversation_history = []
  end

  private

  def get_api_key_for_model(model)
    if model.include?('claude')
      ENV['ANTHROPIC_API_KEY']
    elsif model.include?('llama') || model.include?('meta-llama') || model.include?('openai/gpt-oss')
      ENV['GROQ_API_KEY']
    else
      ENV['OPENAI_API_KEY']
    end
  end
end
