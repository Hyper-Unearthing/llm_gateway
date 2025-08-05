require 'json'

class TodoWriteTool < LlmGateway::Tool
  name 'TodoWrite'
  description 'Create and manage structured task lists'
  input_schema({
    type: 'object',
    properties: {
      todos: {
        type: 'array',
        description: 'Array of todo objects',
        items: {
          type: 'object',
          properties: {
            id: { type: 'string', description: 'Unique identifier' },
            content: { type: 'string', description: 'Task description' },
            status: {
              type: 'string',
              enum: [ 'pending', 'in_progress', 'completed' ],
              description: 'Task status'
            },
            priority: {
              type: 'string',
              enum: [ 'high', 'medium', 'low' ],
              description: 'Task priority'
            }
          },
          required: [ 'id', 'content', 'status', 'priority' ]
        }
      }
    },
    required: [ 'todos' ]
  })

  def execute(input)
    todos = input[:todos]

    # Validate todos structure
    todos.each_with_index do |todo, index|
      unless todo.is_a?(Hash)
        return "Error: Todo at index #{index} is not a hash"
      end

      required_fields = [ 'id', 'content', 'status', 'priority' ]
      missing_fields = required_fields - todo.keys.map(&:to_s)
      unless missing_fields.empty?
        return "Error: Todo at index #{index} missing required fields: #{missing_fields.join(', ')}"
      end

      valid_statuses = [ 'pending', 'in_progress', 'completed' ]
      unless valid_statuses.include?(todo['status'])
        return "Error: Invalid status '#{todo['status']}' in todo #{todo['id']}. Must be one of: #{valid_statuses.join(', ')}"
      end

      valid_priorities = [ 'high', 'medium', 'low' ]
      unless valid_priorities.include?(todo['priority'])
        return "Error: Invalid priority '#{todo['priority']}' in todo #{todo['id']}. Must be one of: #{valid_priorities.join(', ')}"
      end
    end

    # Store todos (in practice, this might be saved to a file or database)
    @todos = todos

    # Generate summary
    total = todos.length
    pending = todos.count { |t| t['status'] == 'pending' }
    in_progress = todos.count { |t| t['status'] == 'in_progress' }
    completed = todos.count { |t| t['status'] == 'completed' }

    summary = "Todo list updated successfully:\n"
    summary += "Total tasks: #{total}\n"
    summary += "Pending: #{pending}, In Progress: #{in_progress}, Completed: #{completed}\n\n"

    # List current todos
    summary += "Current tasks:\n"
    todos.each do |todo|
      status_icon = case todo['status']
      when 'pending' then '⏳'
      when 'in_progress' then '🔄'
      when 'completed' then '✅'
      end

      priority_icon = case todo['priority']
      when 'high' then '🔴'
      when 'medium' then '🟡'
      when 'low' then '🟢'
      end

      summary += "#{status_icon} #{priority_icon} [#{todo['id']}] #{todo['content']}\n"
    end

    summary
  end

  def self.current_todos
    @todos || []
  end
end
