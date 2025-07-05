defmodule Introspex.Postgres.RelationshipAnalyzer do
  @moduledoc """
  Analyzes foreign key relationships between tables to determine
  Ecto associations (belongs_to, has_many, has_one, many_to_many).
  """

  alias Introspex.Postgres.Introspector

  @doc """
  Analyzes all relationships for a given table and returns association definitions.
  """
  def analyze_relationships(repo, table_name, all_tables, schema \\ "public") do
    foreign_keys = Introspector.get_foreign_keys(repo, table_name, schema)

    %{
      belongs_to: analyze_belongs_to(foreign_keys, all_tables),
      has_many: analyze_has_many(repo, table_name, all_tables, schema),
      has_one: analyze_has_one(repo, table_name, all_tables, schema),
      many_to_many: analyze_many_to_many(repo, table_name, all_tables, schema)
    }
  end

  @doc """
  Analyzes belongs_to relationships based on foreign keys in the current table.
  """
  def analyze_belongs_to(foreign_keys, all_tables) do
    foreign_keys
    |> Enum.map(fn fk ->
      # Check if the referenced table exists in our tables list
      if Enum.any?(all_tables, &(&1.name == fk.foreign_table)) do
        %{
          field: singularize(fk.foreign_table),
          table: fk.foreign_table,
          foreign_key: String.to_atom(fk.column_name),
          references: String.to_atom(fk.foreign_column),
          on_update: fk.on_update,
          on_delete: fk.on_delete
        }
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Analyzes has_many relationships by looking for foreign keys in other tables
  that reference this table.
  """
  def analyze_has_many(repo, table_name, all_tables, schema) do
    all_tables
    |> Enum.filter(&(&1.type == :table))
    |> Enum.flat_map(fn other_table ->
      if other_table.name != table_name do
        foreign_keys = Introspector.get_foreign_keys(repo, other_table.name, schema)

        foreign_keys
        |> Enum.filter(&(&1.foreign_table == table_name))
        |> Enum.map(fn fk ->
          # Check if this might be a join table for many-to-many
          if join_table?(other_table.name, repo, schema) do
            nil
          else
            %{
              field: pluralize(other_table.name),
              table: other_table.name,
              foreign_key: String.to_atom(fk.column_name)
            }
          end
        end)
        |> Enum.reject(&is_nil/1)
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.table)
  end

  @doc """
  Analyzes has_one relationships (similar to has_many but with singular naming).
  """
  def analyze_has_one(_repo, _table_name, _all_tables, _schema) do
    # For now, we'll return empty as distinguishing has_one from has_many
    # requires additional heuristics or configuration
    []
  end

  @doc """
  Analyzes many_to_many relationships by detecting join tables.
  """
  def analyze_many_to_many(repo, table_name, all_tables, schema) do
    all_tables
    |> Enum.filter(&(&1.type == :table))
    |> Enum.filter(&join_table?(&1.name, repo, schema))
    |> Enum.flat_map(fn join_table ->
      foreign_keys = Introspector.get_foreign_keys(repo, join_table.name, schema)

      # Find foreign keys that reference our table
      our_fks = Enum.filter(foreign_keys, &(&1.foreign_table == table_name))

      if length(our_fks) > 0 do
        # Find the other foreign keys in the join table
        other_fks = Enum.filter(foreign_keys, &(&1.foreign_table != table_name))

        Enum.map(other_fks, fn other_fk ->
          if Enum.any?(all_tables, &(&1.name == other_fk.foreign_table)) do
            %{
              field: pluralize(other_fk.foreign_table),
              table: other_fk.foreign_table,
              join_through: join_table.name,
              join_keys: [
                {String.to_atom(hd(our_fks).column_name), String.to_atom("id")},
                {String.to_atom("id"), String.to_atom(other_fk.column_name)}
              ]
            }
          else
            nil
          end
        end)
        |> Enum.reject(&is_nil/1)
      else
        []
      end
    end)
    |> Enum.uniq_by(& &1.table)
  end

  @doc """
  Determines if a table is likely a join table for many-to-many relationships.
  """
  def join_table?(table_name, repo, schema) do
    # A join table typically:
    # 1. Has exactly 2 foreign keys
    # 2. May have additional fields like timestamps
    # 3. Often has a composite primary key or minimal columns

    columns = Introspector.get_columns(repo, table_name, schema)
    foreign_keys = Introspector.get_foreign_keys(repo, table_name, schema)
    _primary_keys = Introspector.get_primary_keys(repo, table_name, schema)

    # Check if it has exactly 2 foreign keys
    has_two_fks = length(foreign_keys) == 2

    # Check if most columns are either foreign keys, primary keys, or timestamps
    non_meta_columns =
      Enum.reject(columns, fn col ->
        col.name in ["id", "inserted_at", "updated_at", "created_at"] or
          Enum.any?(foreign_keys, &(&1.column_name == col.name))
      end)

    # It's likely a join table if it has 2 FKs and few other columns
    has_two_fks and length(non_meta_columns) <= 2
  end

  # Helper functions for naming conventions

  defp singularize(table_name) do
    # Simple singularization - in production, use a proper inflector
    cond do
      String.ends_with?(table_name, "ies") ->
        String.replace_suffix(table_name, "ies", "y")

      String.ends_with?(table_name, "es") ->
        String.replace_suffix(table_name, "es", "")

      String.ends_with?(table_name, "s") ->
        String.replace_suffix(table_name, "s", "")

      true ->
        table_name
    end
    |> String.to_atom()
  end

  defp pluralize(table_name) do
    # Simple pluralization - in production, use a proper inflector
    cond do
      String.ends_with?(table_name, "y") ->
        String.replace_suffix(table_name, "y", "ies")

      String.ends_with?(table_name, "s") ->
        table_name

      true ->
        table_name <> "s"
    end
    |> String.to_atom()
  end
end
