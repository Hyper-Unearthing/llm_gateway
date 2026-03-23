require "json"

class StreamAccumulator
  attr_accessor :blocks, :message_hash, :usage_hash

  def initialize
    @message_hash = {}
    @usage_hash = {
      input_tokens: 0,
      cache_creation_input_tokens: 0,
      cache_read_input_tokens: 0,
      output_tokens: 0,
      reasoning_tokens: 0
    }
    @blocks = []
  end

  def result
    message_hash.merge(
      usage: usage_hash,
      content: serialized_blocks
    )
  end

  def push(event)
    return unless event

    case event.type
    when :text_start
      blocks[event.content_index] = {
        type: "text",
        text: ""
      }
      blocks[event.content_index][:text] += event.delta
    when :text_delta, :text_end
      blocks[event.content_index][:text] += event.delta
    when :tool_start
      blocks[event.content_index] = {
        type: "tool_use",
        id: event.id,
        name: event.name,
        input: ""
      }
    when :tool_delta, :tool_end
      blocks[event.content_index][:input] += event.delta
    when :message_start
      message_hash.merge!(event.delta)
      usage_hash.each_key do |key|
        usage_hash[key] += event.usage_increment.fetch(key, 0)
      end
    when :reasoning_start
      blocks[event.content_index] = {
        type: "reasoning",
        reasoning: "",
        signature: ""
      }
      blocks[event.content_index][:reasoning] += event.delta
      blocks[event.content_index][:signature] += event.respond_to?(:signature) ? event.signature : ""
    when :reasoning_delta
      blocks[event.content_index][:reasoning] += event.delta
      blocks[event.content_index][:signature] += event.signature
    when :reasoning_end
      blocks[event.content_index][:reasoning] += event.delta
      blocks[event.content_index][:signature] += event.respond_to?(:signature) ? event.signature : ""
    when :message_delta
      message_hash.merge!(event.delta)
      usage_hash.each_key do |key|
        usage_hash[key] += event.usage_increment.fetch(key, 0)
      end
    when :message_end
    end
  end

  private

  def serialized_blocks
    blocks.map do |block|
      next block unless block[:type] == "tool_use"

      block.merge(input: LlmGateway::Utils.deep_symbolize_keys(parse_tool_input(block[:input])))
    end
  end

  def parse_tool_input(input)
    return {} if input.nil? || input.empty?

    JSON.parse(input)
  rescue JSON::ParserError
    {}
  end
end
