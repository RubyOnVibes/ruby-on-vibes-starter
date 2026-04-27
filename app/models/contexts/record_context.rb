# frozen_string_literal: true

##
# RecordContext - Base class for structured LLM context serialization
#
# Provides schema-driven serialization of ActiveRecord models for LLM consumption.
# Schemas ensure consistency and enable development-mode validation.
#
# Features:
# - JSON Schema export for LLM structured inputs
# - Development-mode validation
# - Consistent serialization across all mentionable models
#
class RecordContext
  class << self
    
    ##
    # Define the schema for this context
    # Delegates to RubyLLM::Schema DSL
    #
    def schema(&block)
      # Capture context class name outside the block
      context_name = name&.sub('Context', '') || 'Record'
      
      @schema_class ||= Class.new(RubyLLM::Schema) do
        # Set schema name based on context class
        name context_name
      end
      
      @schema_class.class_eval(&block) if block_given?
      @schema_class
    end
    
    ##
    # Get the schema class for this context
    #
    def schema_class
      @schema_class || raise(NotImplementedError, "#{name} must define a schema")
    end
    
    ##
    # Create context from an ActiveRecord instance
    # Override this in subclasses
    #
    def from_record(record)
      raise NotImplementedError, "#{name} must implement .from_record(record)"
    end
  end
  
  attr_reader :data
  
  def initialize(data = {})
    @data = data.with_indifferent_access
    validate!
  end
  
  ##
  # Validate data against schema
  # Raises error if invalid in development
  #
  def validate!
    schema_class = self.class.schema_class
    
    # RubyLLM::Schema doesn't have built-in validation yet,
    # but we can check required fields
    json_schema = schema_class.new.to_json_schema
    required = json_schema.dig(:schema, :required) || []
    
    required.each do |field|
      unless @data.key?(field) || @data.key?(field.to_sym)
        raise ArgumentError, "#{self.class.name}: Missing required field '#{field}'"
      end
    end
    
    true
  end
  
  ##
  # Export as JSON Schema
  # Used by LLM for understanding structure
  #
  def to_json_schema
    self.class.schema_class.new.to_json_schema
  end
  
  ##
  # Serialize to hash for LLM consumption
  #
  def to_h
    @data
  end
  
  ##
  # Serialize to JSON
  #
  def to_json(*args)
    @data.to_json(*args)
  end
  
  ##
  # String representation for debugging
  #
  def to_s
    "#{self.class.name}(#{@data.inspect})"
  end
  
  ##
  # Format for LLM instructions
  # Returns schema + data in a structured format
  #
  # @param format [Symbol] :json, :yaml, or :schema_plus_data
  # @return [String] Formatted context
  #
  def to_llm_instruction(format: :json)
    case format
    when :json
      to_json
    when :yaml
      require 'yaml'
      @data.to_yaml
    when :schema_plus_data
      schema = to_json_schema
      <<~TEXT
        Schema: #{schema[:name]}
        Description: #{schema[:description]}
        Structure: #{schema[:schema].to_json}
        Data: #{@data.to_json}
      TEXT
    else
      to_json
    end
  end
  
  ##
  # Method missing for hash-like access
  #
  def method_missing(method_name, *args, &block)
    if @data.key?(method_name)
      @data[method_name]
    else
      super
    end
  end
  
  def respond_to_missing?(method_name, include_private = false)
    @data.key?(method_name) || super
  end
end