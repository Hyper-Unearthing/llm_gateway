class Agent
  def initialize(prompt_class, model, api_key)
    @prompt_class = prompt_class
    @model = model
    @api_key = api_key
    @transcript = []
  end

  def run(user_input, &block)
    @transcript << { role: 'user', content: [ { type: 'text', text: user_input } ] }

    begin
      prompt = @prompt_class.new(@model, @transcript, @api_key)
      result = prompt.post
      process_response(result[:choices][0][:content], &block)
    rescue => e
      yield({ type: 'error', message: e.message }) if block_given?
      raise e
    end
  end

  private

  def process_response(response, &block)
    @transcript << { role: 'assistant', content: response }

    response.each do |message|
      yield(message) if block_given?

      if message[:type] == 'text'
        # Text response processed
      elsif message[:type] == 'tool_use'
        result = handle_tool_use(message)

        tool_result = {
          type: 'tool_result',
          tool_use_id: message[:id],
          content: result
        }
        @transcript << { role: 'user', content: [ tool_result ] }

        yield(tool_result) if block_given?

        follow_up_prompt = @prompt_class.new(@model, @transcript, @api_key)
        follow_up = follow_up_prompt.post

        process_response(follow_up[:choices][0][:content], &block) if follow_up[:choices][0][:content]
      end
    end

    response
  end

  def handle_tool_use(message)
    tool_class = @prompt_class.find_tool(message[:name])
    if tool_class
      tool = tool_class.new
      tool.execute(message[:input])
    else
      "Unknown tool: #{message[:name]}"
    end
  rescue StandardError => e
    "Error executing tool: #{e.message}"
  end
end