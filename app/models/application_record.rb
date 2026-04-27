class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  def self.validates_variable_content_type(*attributes)
    validates_each(*attributes) do |record, attribute, value|
      next unless value.attached?

      unless ActiveStorage.variable_content_types.include?(value.content_type)
        record.errors.add(attribute, :content_type_must_be_resizable)
      end
    end
  end
end
