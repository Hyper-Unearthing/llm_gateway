# frozen_string_literal: true

module LlmGateway
  module Utils
    module_function

    def symbolize_keys(hash)
      hash.to_h.transform_keys { |key| key.respond_to?(:to_sym) ? key.to_sym : key }
    end

    def deep_symbolize_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested_value), result|
          result[symbolize_key(key)] = deep_symbolize_keys(nested_value)
        end
      when Array
        value.map { |item| deep_symbolize_keys(item) }
      else
        value
      end
    end

    def present?(value)
      !blank?(value)
    end

    def presence(value)
      present?(value) ? value : nil
    end

    def blank?(value)
      case value
      when nil, false
        true
      when true, Numeric
        false
      when String
        value.match?(/\A[[:space:]]*\z/)
      else
        value.respond_to?(:empty?) ? !!value.empty? : false
      end
    end

    def symbolize_key(key)
      key.respond_to?(:to_sym) ? key.to_sym : key
    rescue StandardError
      key
    end
  end
end

class Class
  def class_attribute(*names, instance_accessor: true, instance_reader: instance_accessor, instance_writer: instance_accessor, instance_predicate: true, default: nil)
    names.each do |name|
      ivar = :"@#{name}"
      instance_variable_set(ivar, default)

      unset = Object.new

      define_singleton_method(name) do |value = unset|
        unless value.equal?(unset)
          instance_variable_set(ivar, value)
          next value
        end

        if instance_variable_defined?(ivar)
          instance_variable_get(ivar)
        elsif superclass.respond_to?(name)
          superclass.public_send(name)
        end
      end

      define_singleton_method("#{name}=") do |value|
        instance_variable_set(ivar, value)
      end

      if instance_reader
        define_method(name) do
          if instance_variable_defined?(ivar)
            instance_variable_get(ivar)
          else
            self.class.public_send(name)
          end
        end
      end

      define_method("#{name}=") { |value| instance_variable_set(ivar, value) } if instance_writer

      if instance_predicate
        define_method("#{name}?") { !!public_send(name) }
      end
    end
  end
end

class Object
  def blank?
    LlmGateway::Utils.blank?(self)
  end

  def present?
    LlmGateway::Utils.present?(self)
  end

  def presence
    LlmGateway::Utils.presence(self)
  end
end

class Hash
  def symbolize_keys
    transform_keys { |key| LlmGateway::Utils.symbolize_key(key) }
  end

  def symbolize_keys!
    replace(symbolize_keys)
  end

  def deep_symbolize_keys
    LlmGateway::Utils.deep_symbolize_keys(self)
  end

  def deep_symbolize_keys!
    replace(deep_symbolize_keys)
  end

  unless method_defined?(:except)
    def except(*keys)
      reject { |key, _| keys.include?(key) }
    end
  end

  unless method_defined?(:except!)
    def except!(*keys)
      keys.each { |key| delete(key) }
      self
    end
  end
end
