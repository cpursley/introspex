defmodule Introspex.Postgres.Introspector do
  @moduledoc """
  Introspects PostgreSQL database schema including tables, views, materialized views,
  columns, constraints, and foreign keys.
  """

  @doc """
  Lists all tables, views, and materialized views in the specified schema.
  """
  def list_tables(repo, schema \\ "public", exclude_views \\ false) do
    base_query = """
    SELECT 
      c.relname AS table_name,
      CASE c.relkind
        WHEN 'r' THEN 'table'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized_view'
      END AS table_type,
      obj_description(c.oid, 'pg_class') AS comment
    FROM pg_catalog.pg_class c
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1
      AND c.relkind IN ('r', 'v', 'm')
    """

    query =
      if exclude_views do
        base_query <> " AND c.relkind = 'r'"
      else
        base_query
      end

    query = query <> " ORDER BY c.relname"

    case repo.query(query, [schema]) do
      {:ok, result} ->
        Enum.map(result.rows, fn [name, type, comment] ->
          %{
            name: name,
            type: String.to_atom(type),
            comment: comment
          }
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets detailed column information for a specific table.
  """
  def get_columns(repo, table_name, schema \\ "public") do
    query = """
    SELECT 
      a.attname AS column_name,
      pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
      a.attnotnull AS not_null,
      pg_get_expr(d.adbin, d.adrelid) AS default_value,
      col_description(c.oid, a.attnum) AS comment,
      a.attnum AS ordinal_position,
      CASE 
        WHEN t.typtype = 'e' THEN 
          ARRAY(
            SELECT e.enumlabel 
            FROM pg_enum e 
            WHERE e.enumtypid = a.atttypid 
            ORDER BY e.enumsortorder
          )
        ELSE NULL
      END AS enum_values
    FROM pg_catalog.pg_attribute a
    INNER JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    INNER JOIN pg_catalog.pg_type t ON t.oid = a.atttypid
    LEFT JOIN pg_catalog.pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
    WHERE n.nspname = $1
      AND c.relname = $2
      AND a.attnum > 0
      AND NOT a.attisdropped
    ORDER BY a.attnum
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, result} ->
        Enum.map(result.rows, fn [name, type, not_null, default, comment, position, enum_values] ->
          %{
            name: name,
            data_type: type,
            not_null: not_null,
            default: parse_default(default),
            comment: comment,
            position: position,
            enum_values: enum_values
          }
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets primary key information for a table.
  """
  def get_primary_keys(repo, table_name, schema \\ "public") do
    query = """
    SELECT a.attname AS column_name
    FROM pg_catalog.pg_constraint con
    INNER JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    INNER JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(con.conkey)
    WHERE n.nspname = $1
      AND c.relname = $2
      AND con.contype = 'p'
    ORDER BY array_position(con.conkey, a.attnum)
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, result} ->
        Enum.map(result.rows, fn [column_name] -> column_name end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets foreign key relationships for a table.
  """
  def get_foreign_keys(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      con.conname AS constraint_name,
      a.attname AS column_name,
      fn.nspname AS foreign_schema,
      fc.relname AS foreign_table,
      fa.attname AS foreign_column,
      con.confupdtype AS on_update,
      con.confdeltype AS on_delete
    FROM pg_catalog.pg_constraint con
    INNER JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    INNER JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(con.conkey)
    INNER JOIN pg_catalog.pg_class fc ON fc.oid = con.confrelid
    INNER JOIN pg_catalog.pg_namespace fn ON fn.oid = fc.relnamespace
    INNER JOIN pg_catalog.pg_attribute fa ON fa.attrelid = fc.oid AND fa.attnum = ANY(con.confkey)
    WHERE n.nspname = $1
      AND c.relname = $2
      AND con.contype = 'f'
    ORDER BY con.conname, array_position(con.conkey, a.attnum)
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, result} ->
        result.rows
        |> Enum.group_by(fn [constraint_name | _] -> constraint_name end)
        |> Enum.map(fn {constraint_name, rows} ->
          [_, column_name, foreign_schema, foreign_table, foreign_column, on_update, on_delete] =
            hd(rows)

          %{
            constraint_name: constraint_name,
            column_name: column_name,
            foreign_schema: foreign_schema,
            foreign_table: foreign_table,
            foreign_column: foreign_column,
            on_update: decode_action(on_update),
            on_delete: decode_action(on_delete)
          }
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets unique constraints for a table (excluding primary key).
  """
  def get_unique_constraints(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      con.conname AS constraint_name,
      ARRAY_AGG(a.attname ORDER BY array_position(con.conkey, a.attnum)) AS columns
    FROM pg_catalog.pg_constraint con
    INNER JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    INNER JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(con.conkey)
    WHERE n.nspname = $1
      AND c.relname = $2
      AND con.contype = 'u'
    GROUP BY con.conname
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, result} ->
        Enum.map(result.rows, fn [constraint_name, columns] ->
          %{
            constraint_name: constraint_name,
            columns: columns
          }
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets check constraints for a table.
  """
  def get_check_constraints(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      con.conname AS constraint_name,
      pg_get_constraintdef(con.oid) AS definition
    FROM pg_catalog.pg_constraint con
    INNER JOIN pg_catalog.pg_class c ON c.oid = con.conrelid
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = $1
      AND c.relname = $2
      AND con.contype = 'c'
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, result} ->
        Enum.map(result.rows, fn [constraint_name, definition] ->
          %{
            constraint_name: constraint_name,
            definition: definition
          }
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Gets indexes for a table.
  """
  def get_indexes(repo, table_name, schema \\ "public") do
    query = """
    SELECT
      i.relname AS index_name,
      ARRAY_AGG(a.attname ORDER BY array_position(ix.indkey::int[], a.attnum)) AS columns,
      ix.indisunique AS is_unique,
      ix.indisprimary AS is_primary,
      pg_get_indexdef(i.oid) AS definition
    FROM pg_catalog.pg_index ix
    INNER JOIN pg_catalog.pg_class c ON c.oid = ix.indrelid
    INNER JOIN pg_catalog.pg_class i ON i.oid = ix.indexrelid
    INNER JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    INNER JOIN pg_catalog.pg_attribute a ON a.attrelid = c.oid AND a.attnum = ANY(ix.indkey::int[])
    WHERE n.nspname = $1
      AND c.relname = $2
      AND NOT ix.indisprimary
    GROUP BY i.relname, i.oid, ix.indisunique, ix.indisprimary
    """

    case repo.query(query, [schema, table_name]) do
      {:ok, result} ->
        Enum.map(result.rows, fn [index_name, columns, is_unique, is_primary, definition] ->
          %{
            index_name: index_name,
            columns: columns,
            unique: is_unique,
            primary: is_primary,
            definition: definition
          }
        end)

      {:error, error} ->
        {:error, error}
    end
  end

  # Helper functions

  @doc """
  Parses PostgreSQL default values, removing type casts and sequence defaults.
  """
  def parse_default(nil), do: nil

  def parse_default(default) do
    # Clean up common PostgreSQL default formats
    cond do
      # Check for sequence defaults first
      String.match?(default, ~r/nextval\(/) ->
        nil

      # Remove type casting
      String.match?(default, ~r/^'(.*)'::\w+$/) ->
        default
        |> String.replace(~r/^'(.*)'::\w+$/, "\\1")
        |> case do
          "" -> nil
          value -> value
        end

      # Return empty strings as nil
      default == "" ->
        nil

      # Return other values unchanged
      true ->
        default
    end
  end

  @doc """
  Decodes PostgreSQL foreign key action codes to atoms.
  """
  def decode_action("a"), do: :no_action
  def decode_action("r"), do: :restrict
  def decode_action("c"), do: :cascade
  def decode_action("n"), do: :set_null
  def decode_action("d"), do: :set_default
  def decode_action(_), do: :no_action
end
