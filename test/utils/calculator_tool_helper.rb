# frozen_string_literal: true

module CalculatorToolHelper
  def math_operation_tool
    {
      name: "math_operation",
      description: "Perform a basic math operation on two numbers",
      input_schema: {
        type: "object",
        properties: {
          a: { type: "number", description: "The first number" },
          b: { type: "number", description: "The second number" },
          operation: {
            type: "string",
            enum: %w[add subtract multiply divide],
            description: "The operation to perform"
          }
        },
        required: [ "a", "b", "operation" ]
      }
    }
  end

  def evaluate_math_operation(input)
    a = input[:a] || input["a"]
    b = input[:b] || input["b"]
    operation = input[:operation] || input["operation"]

    case operation
    when "add"
      a + b
    when "subtract"
      a - b
    when "multiply"
      a * b
    when "divide"
      a / b
    else
      raise "Unsupported operation: #{operation.inspect}"
    end
  end
end
