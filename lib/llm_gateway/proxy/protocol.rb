# frozen_string_literal: true

module LlmGateway
  module Proxy
    # The only string-to-class mapping in the application. Adapter names are
    # protocol values used to cross the proxy boundary; runtime code uses the
    # adapter classes themselves.
    module Protocol
      ADAPTERS = {
        "anthropic-messages" => LlmGateway::Adapters::Anthropic::MessagesAdapter,
        "openai-completions" => LlmGateway::Adapters::OpenAI::ChatCompletionsAdapter,
        "openai-responses" => LlmGateway::Adapters::OpenAI::ResponsesAdapter,
        "openai-codex" => LlmGateway::Adapters::OpenAICodex::ResponsesAdapter,
        "groq-completions" => LlmGateway::Adapters::Groq::ChatCompletionsAdapter
      }.freeze
      ADAPTER_NAMES = ADAPTERS.invert.freeze

      module_function

      def load_adapter(name)
        ADAPTERS.fetch(name.to_s) do
          raise LlmGateway::Errors::UnsupportedProvider, "Unknown proxy adapter: #{name}"
        end
      end

      def dump_adapter(selector)
        adapter_class = adapter_class_for(selector)
        ADAPTER_NAMES.fetch(adapter_class) do
          raise LlmGateway::Errors::UnsupportedProvider,
            "Adapter is not supported by the proxy: #{adapter_class}"
        end
      end

      def adapter_class(selector)
        adapter_class = adapter_class_for(selector)
        dump_adapter(adapter_class)
        adapter_class
      end

      def adapter_class_for(selector)
        return selector.adapter_class if selector.respond_to?(:adapter_class)
        return selector if selector.is_a?(Class) && selector <= LlmGateway::Adapters::Adapter
        return selector.class if selector.is_a?(LlmGateway::Adapters::Adapter)

        raise ArgumentError, "Expected an adapter class, definition, or instance, got #{selector.inspect}"
      end
      private_class_method :adapter_class_for
    end
  end
end
