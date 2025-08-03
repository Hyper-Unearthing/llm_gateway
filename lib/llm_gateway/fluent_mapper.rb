# frozen_string_literal: true

module LlmGateway
  module FluentMapper
    def self.extended(base)
      base.instance_variable_set(:@mappers, {})
      base.instance_variable_set(:@mappings, [])
    end

    def inherited(subclass)
      super
      # Copy parent's mappers and mappings to the subclass
      subclass.instance_variable_set(:@mappers, @mappers.dup)
      subclass.instance_variable_set(:@mappings, @mappings.dup)
    end

    def mapper(name, &block)
      @mappers[name] = block
    end

    def map(field_or_data, options = {}, &block)
      # If called with a single argument and no block, it's the class method usage
      if block.nil? && options.empty? && !field_or_data.is_a?(Symbol) && !field_or_data.is_a?(String)
        return new(field_or_data).call
      end

      # Otherwise it's the field mapping usage
      @mappings << { field: field_or_data, options: options, block: block }
    end

    def new(data)
      MapperInstance.new(data, @mappers, @mappings)
    end

    class MapperInstance
      def initialize(data, mappers, mappings)
        @data = data.respond_to?(:with_indifferent_access) ? data.with_indifferent_access : data
        @mappers = mappers
        @mappings = mappings
        @mapper_definitions = {}

        # Execute mapper definitions
        mappers.each do |name, block|
          @mapper_definitions[name] = MapperDefinition.new
          @mapper_definitions[name].instance_eval(&block)
        end
      end

      def call
        result = {}

        @mappings.each do |mapping|
          field = mapping[:field]
          options = mapping[:options]
          block = mapping[:block]

          from_path = options[:from] || field.to_s
          default_value = options[:default]

          value = get_nested_value(@data, from_path)
          value = default_value if value.nil? && !default_value.nil?

          value = instance_exec(field, value, &block) if block

          result[field] = value
        end

        LlmGateway::Utils.deep_symbolize_keys(result)
      end

      def map_single(data, options = {})
        mapper_name = options[:with]
        default_value = options[:default]
        return default_value if data.nil? && !default_value.nil?
        return data unless mapper_name && @mapper_definitions[mapper_name]

        # Apply with_indifferent_access to data
        data = data.respond_to?(:with_indifferent_access) ? data.with_indifferent_access : data

        mapper_def = @mapper_definitions[mapper_name]
        result = {}

        mapper_def.mappings.each do |mapping|
          field = mapping[:field]
          map_options = mapping[:options]
          block = mapping[:block]

          from_path = map_options[:from] || field.to_s
          field_default_value = map_options[:default]

          value = get_nested_value(data, from_path)
          value = field_default_value if value.nil? && !field_default_value.nil?

          value = instance_exec(field, value, &block) if block

          result[field.to_s] = value
        end

        result
      end

      def map_collection(collection, options = {})
        default_value = options[:default]
        return default_value if collection.nil? && !default_value.nil?
        return [] if collection.nil?

        collection.map { |item| map_single(item, options) }
      end

      private

      def get_nested_value(data, path)
        return data[path] if data.respond_to?(:[]) && data.key?(path)
        return data[path.to_sym] if data.respond_to?(:[]) && data.key?(path.to_sym)
        return data[path.to_s] if data.respond_to?(:[]) && data.key?(path.to_s)

        keys = path.split(".")
        current = data

        keys.each do |key|
          return nil unless current.respond_to?(:[])

          current = current[key] || current[key.to_sym] || current[key.to_s]

          return nil if current.nil?
        end

        current
      end
    end

    class MapperDefinition
      attr_reader :mappings

      def initialize
        @mappings = []
      end

      def map(field, options = {}, &block)
        @mappings << { field: field, options: options, block: block }
      end
    end
  end
end
