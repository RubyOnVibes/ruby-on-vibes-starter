# frozen_string_literal: true

##
# Shared role management for workspace membership.
#
# Include this concern in any model that needs workspace role support
# (e.g., Member, Invitation). Requires a `roles` json/jsonb column.
#
# Database-agnostic: works with both PostgreSQL (jsonb) and SQLite (json).
#
# @example Usage
#   class Member < ApplicationRecord
#     include Workspace::Roles
#   end
#
# @example Checking roles
#   member.admin?        # => true/false
#   member.member?       # => true/false
#   member.active_roles  # => [:admin, :member]
#
# @example Setting roles
#   member.admin = true
#   member.member = "1"  # auto-cast to boolean
#
# @example Querying
#   Member.admin   # => all admin members
#   Member.member  # => all members with member role
#
module Workspace::Roles
  extend ActiveSupport::Concern

  ROLES = %i[admin member].freeze

  included do
    # Expose ROLES at class level (e.g., Member::ROLES)
    const_set(:ROLES, Workspace::Roles::ROLES) unless const_defined?(:ROLES, false)

    ROLES.each do |role|
      scope role, -> { where(*role_query_condition(role)) }

      # Getter: returns boolean value for this role
      define_method(role) do
        ActiveRecord::Type::Boolean.new.cast(roles_hash[role.to_s])
      end

      # Setter: stores boolean value for this role
      define_method(:"#{role}=") do |value|
        cast_value = ActiveRecord::Type::Boolean.new.cast(value)
        write_attribute(:roles, roles_hash.merge(role.to_s => cast_value))
      end

      # Predicate: alias for getter
      define_method(:"#{role}?") { send(role) }
    end
  end

  ##
  # Returns roles as a hash, handling both Hash and JSON string formats.
  #
  # @return [Hash] the roles hash
  #
  def roles_hash
    case roles
    when Hash
      roles
    when String
      JSON.parse(roles) rescue {}
    else
      {}
    end
  end

  class_methods do
    ##
    # Generates a database-agnostic WHERE condition for querying JSON roles.
    #
    # @param role [Symbol] the role to query for
    # @return [Array] SQL condition with bind parameters
    #
    def role_query_condition(role)
      adapter = connection_db_config.adapter

      case adapter
      when /postgresql/
        # PostgreSQL: use efficient JSONB containment operator
        ["roles @> ?", { role => true }.to_json]
      when /sqlite/
        # SQLite: use json_extract (JSON1 extension, included by default in SQLite 3.38+)
        # json_extract returns 1 for true in SQLite
        ["json_extract(roles, ?) = ?", "$.#{role}", 1]
      else
        # Fallback: use json_extract syntax (works for most modern databases)
        ["json_extract(roles, ?) = ?", "$.#{role}", true]
      end
    end

    private

    def connection_db_config
      ActiveRecord::Base.configurations.find_db_config(Rails.env)
    end
  end

  ##
  # Returns array of roles currently enabled for this record.
  #
  # @return [Array<Symbol>] active role names
  #
  def active_roles
    ROLES.select { |role| public_send(:"#{role}?") }
  end
end
