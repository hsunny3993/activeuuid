require 'active_record'
require 'active_support/concern'


module ActiveUUID
  module Patches
    module Migrations
      def uuid(*column_names)
        options = column_names.extract_options!
        column_names.each do |name|
          type = ActiveRecord::Base.connection.adapter_name.downcase == 'postgresql' ? 'uuid' : 'binary(16)'
          column(name, "#{type}#{' PRIMARY KEY' if options.delete(:primary_key)}", options)
        end
      end
    end

    module Quoting
      extend ActiveSupport::Concern

      included do
        def quote_with_visiting(value)
          case value
          when ActiveModel::Type::Binary::Data
            value = UUIDTools::UUID.serialize(value.to_s)
            "#{value.quoted_id}"
          else
            quote_without_visiting(value)
          end
        end

        def type_cast_with_visiting(value, column = nil)
          value = UUIDTools::UUID.serialize(value) if column && column.type == :uuid
          type_cast_without_visiting(value, column)
        end

        def type_cast_with_uuid(value)
          return UUIDTools::UUID.serialize(value) if type == :uuid
          type_cast_without_uuid(value)
        end

        def type_cast_code_with_uuid(var_name)
          return "UUIDTools::UUID.serialize(#{var_name})" if type == :uuid
          type_cast_code_without_uuid(var_name)
        end

        # alias_method_chain :quote, :visiting
        # alias_method_chain :type_cast, :visiting

        alias_method :quote_without_visiting, :quote
        alias_method :quote, :quote_with_visiting

        alias_method :type_cast_without_visiting, :type_cast
        alias_method :type_cast, :type_cast_with_visiting

        # alias_method_chain :type_cast, :uuid
        # alias_method_chain :type_cast_code, :uuid if ActiveRecord::VERSION::MAJOR < 4

        alias_method :type_cast_without_uuid, :type_cast
        alias_method :type_cast, :type_cast_with_uuid

        alias_method :type_cast_code_without_uuid, :type_cast_code if ActiveRecord::VERSION::MAJOR < 4
        alias_method :type_cast_code, :type_cast_code_with_uuid if ActiveRecord::VERSION::MAJOR < 4
      end
    end

    module SchemaStatements
      extend ActiveSupport::Concern

      included do
        def native_database_types_with_uuid
          @native_database_types ||= native_database_types_without_uuid.merge(uuid: { name: 'binary', limit: 16 })
        end

        def native_database_types
          ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::NATIVE_DATABASE_TYPES.merge(uuid: { name: 'binary', limit: 16 })
        end

        def fetch_type_metadata(sql_type)
          cast_type = lookup_cast_type(sql_type)
          ActiveRecord::ConnectionAdapters::SqlTypeMetadata.new(
            sql_type: sql_type,
            type: (sql_type == 'binary(16)' ? :uuid : cast_type.type),
            limit: cast_type.limit,
            precision: cast_type.precision,
            scale: cast_type.scale,
            )
        end

        alias_method :native_database_types_without_uuid, :native_database_types
        alias_method :native_database_types, :native_database_types_with_uuid
      end
    end

    def self.apply!
      ActiveRecord::ConnectionAdapters::Table.send :include, Migrations if defined? ActiveRecord::ConnectionAdapters::Table
      ActiveRecord::ConnectionAdapters::TableDefinition.send :include, Migrations if defined? ActiveRecord::ConnectionAdapters::TableDefinition

      ActiveRecord::ConnectionAdapters::Quoting.send :include, Quoting
      ActiveRecord::ConnectionAdapters::SchemaStatements.send :include, SchemaStatements

      ActiveRecord::ConnectionAdapters::Mysql2Adapter.send :include, Quoting if defined? ActiveRecord::ConnectionAdapters::Mysql2Adapter
    end
  end
end
