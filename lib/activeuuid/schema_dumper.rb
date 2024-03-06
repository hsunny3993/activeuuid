require 'active_record/schema_dumper'

class ActiveRecord::SchemaDumper
  private

  def table(table, stream)
    columns = @connection.columns(table)
    begin
      self.table_name = table

      tbl = StringIO.new

      pk_is_activeuuid = false

      # first dump primary key column
      pk = @connection.primary_key(table)

      tbl.print "  create_table #{remove_prefix_and_suffix(table).inspect}"

      case pk
      when String
        tbl.print ", primary_key: #{pk.inspect}" unless pk == "id"
        pkcol = columns.detect { |c| c.name == pk }

        if pkcol.sql_type == "binary(16)"
          tbl.print ", id: false"
          pk_is_activeuuid = true
        else
          pkcolspec = column_spec_for_primary_key(pkcol)
          unless pkcolspec.empty?
            if pkcolspec != pkcolspec.slice(:id, :default)
              pkcolspec = { id: { type: pkcolspec.delete(:id), **pkcolspec }.compact }
            end
            tbl.print ", #{format_colspec(pkcolspec)}"
          end
        end
      when Array
        tbl.print ", primary_key: #{pk.inspect}"
      else
        tbl.print ", id: false"
      end

      table_options = @connection.table_options(table)
      if table_options.present?
        tbl.print ", #{format_options(table_options)}"
      end

      tbl.puts ", force: :cascade do |t|"

      if table == 'oauth_access_grants'
        puts table
      end

      # then dump all non-primary key columns
      columns.each do |column|
        native_database_types = ActiveRecord::ConnectionAdapters::AbstractMysqlAdapter::NATIVE_DATABASE_TYPES.merge(uuid: { name: 'binary', limit: 16 })

        raise StandardError, "Unknown type '#{column.sql_type}' for column '#{column.name}'" if native_database_types[column.type].nil?
        next if !pk_is_activeuuid and column.name == pk

        if column.sql_type == 'binary(16)' || column.sql_type == 'binary(16,0)'
          type = :uuid
          colspec = {limit: 16}
        else
          type, colspec = column_spec(column)
        end

        if type.is_a?(Symbol)
          tbl.print "    t.#{type} #{column.name.inspect}"
        else
          tbl.print "    t.column #{column.name.inspect}, #{type.inspect}"
        end
        tbl.print ", #{format_colspec(colspec)}" if colspec.present?
        tbl.puts
      end

      indexes_in_create(table, tbl)
      check_constraints_in_create(table, tbl) if @connection.supports_check_constraints?
      exclusion_constraints_in_create(table, tbl) if @connection.supports_exclusion_constraints?
      unique_constraints_in_create(table, tbl) if @connection.supports_unique_constraints?

      tbl.puts "  end"
      tbl.puts

      stream.print tbl.string
    rescue => e
      stream.puts "# Could not dump table #{table.inspect} because of following #{e.class}"
      stream.puts "#   #{e.message}"
      stream.puts
    ensure
      self.table_name = nil
    end
  end
end
