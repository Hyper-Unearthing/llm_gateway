# frozen_string_literal: true

require_relative "../adapter"
require_relative "acts_like_messages"
require_relative "../anthropic_option_mapper"
require_relative "../input_message_sanitizer"
require_relative "input_mapper"
require_relative "output_mapper"
require_relative "stream_mapper"

module LlmGateway
  module Adapters
    module Anthropic
      class MessagesAdapter < Adapter
        include ActsLikeAnthropicMessages
      end
    end
  end
end
