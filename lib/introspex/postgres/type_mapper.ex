defmodule Introspex.Postgres.TypeMapper do
  @moduledoc """
  Maps PostgreSQL data types to Ecto schema types.
  """

  @doc """
  Maps a PostgreSQL data type string to an Ecto type atom or tuple.
  """
  def map_type(postgres_type, enum_values \\ nil) do
    # Clean up the type string (remove size constraints, etc.)
    base_type =
      postgres_type
      |> String.downcase()
      |> String.split("(")
      |> hd()
      |> String.trim()

    case base_type do
      # Integer types
      "smallint" ->
        :integer

      "integer" ->
        :integer

      "int" ->
        :integer

      "int2" ->
        :integer

      "int4" ->
        :integer

      "int8" ->
        :integer

      "bigint" ->
        :integer

      "serial" ->
        :integer

      "bigserial" ->
        :integer

      "smallserial" ->
        :integer

      # Decimal/Float types
      "decimal" ->
        :decimal

      "numeric" ->
        :decimal

      "real" ->
        :float

      "float" ->
        :float

      "float4" ->
        :float

      "float8" ->
        :float

      "double precision" ->
        :float

      "money" ->
        :decimal

      # String types
      "character varying" ->
        :string

      "varchar" ->
        :string

      "character" ->
        :string

      "char" ->
        :string

      "text" ->
        :string

      "citext" ->
        :string

      "name" ->
        :string

      # UUID
      "uuid" ->
        :binary_id

      # Boolean
      "boolean" ->
        :boolean

      "bool" ->
        :boolean

      # Date/Time types
      "timestamp" ->
        :naive_datetime

      "timestamp without time zone" ->
        :naive_datetime

      "timestamp with time zone" ->
        :utc_datetime

      "timestamptz" ->
        :utc_datetime

      "date" ->
        :date

      "time" ->
        :time

      "time without time zone" ->
        :time

      "time with time zone" ->
        :time

      # Could be a custom type
      "interval" ->
        :string

      # Binary types
      "bytea" ->
        :binary

      "bit" ->
        :string

      "bit varying" ->
        :string

      # JSON types
      "json" ->
        :map

      "jsonb" ->
        :map

      # Array types
      type ->
        cond do
          String.ends_with?(type, "[]") ->
            inner_type = String.trim_trailing(type, "[]")
            {:array, map_type(inner_type)}

          String.starts_with?(type, "_") ->
            # PostgreSQL array types with underscore prefix
            inner_type = String.trim_leading(type, "_")
            {:array, map_type(inner_type)}

          true ->
            # Continue to other type checks
            map_other_types(type, enum_values)
        end
    end
  end

  defp map_other_types(base_type, enum_values) do
    case base_type do
      # Network types
      "inet" ->
        :string

      "cidr" ->
        :string

      "macaddr" ->
        :string

      "macaddr8" ->
        :string

      # Geometric types (PostGIS)
      "geometry" ->
        {:geometry, "Geometry"}

      "geography" ->
        {:geography, "Geography"}

      "point" ->
        {:geometry, "Point"}

      "linestring" ->
        {:geometry, "LineString"}

      "polygon" ->
        {:geometry, "Polygon"}

      "multipoint" ->
        {:geometry, "MultiPoint"}

      "multilinestring" ->
        {:geometry, "MultiLineString"}

      "multipolygon" ->
        {:geometry, "MultiPolygon"}

      "geometrycollection" ->
        {:geometry, "GeometryCollection"}

      # Full text search
      "tsvector" ->
        :string

      "tsquery" ->
        :string

      # Range types
      "int4range" ->
        :string

      "int8range" ->
        :string

      "numrange" ->
        :string

      "tsrange" ->
        :string

      "tstzrange" ->
        :string

      "daterange" ->
        :string

      # Enum types
      "user-defined" when is_list(enum_values) and length(enum_values) > 0 ->
        {:enum, Enum.map(enum_values, &String.to_atom/1)}

      # XML
      "xml" ->
        :string

      # Other PostgreSQL specific types
      "oid" ->
        :integer

      "regclass" ->
        :string

      "regproc" ->
        :string

      "regtype" ->
        :string

      # Default fallback
      _ ->
        :string
    end
  end

  @doc """
  Returns the Ecto field type definition as a string for code generation.
  """
  def type_to_string(type) do
    case type do
      {:array, inner_type} ->
        "{:array, #{type_to_string(inner_type)}}"

      {:enum, values} ->
        values_string =
          values
          |> Enum.map(&inspect/1)
          |> Enum.join(", ")

        "Ecto.Enum, values: [#{values_string}]"

      {:geometry, _geom_type} ->
        "Geo.PostGIS.Geometry"

      {:geography, _geog_type} ->
        "Geo.PostGIS.Geography"

      atom when is_atom(atom) ->
        ":#{atom}"
    end
  end

  @doc """
  Determines if a field is an Ecto timestamp field.
  Ecto specifically expects "inserted_at" and "updated_at" for the timestamps() macro.
  """
  def ecto_timestamp_field?(field_name) do
    field_name in ["inserted_at", "updated_at"]
  end

  @doc """
  Checks if columns are compatible with Ecto's timestamps() macro.
  Returns true only if both inserted_at and updated_at exist with compatible types.
  """
  def ecto_timestamps_compatible?(columns) do
    timestamp_columns =
      columns
      |> Enum.filter(&ecto_timestamp_field?(&1.name))
      |> Map.new(&{&1.name, &1})

    case timestamp_columns do
      %{"inserted_at" => inserted, "updated_at" => updated} ->
        # Check if both have timestamp-compatible types
        compatible_type?(inserted.data_type) && compatible_type?(updated.data_type)

      _ ->
        false
    end
  end

  defp compatible_type?(type) do
    String.downcase(type) in [
      "timestamp",
      "timestamptz",
      "timestamp without time zone",
      "timestamp with time zone"
    ]
  end

  @doc """
  Returns a list of supported PostGIS types that require special handling.
  """
  def postgis_types do
    ~w(geometry geography point linestring polygon multipoint multilinestring multipolygon geometrycollection)
  end

  @doc """
  Checks if a type requires a special import or alias.
  """
  def requires_special_import?(type) do
    case type do
      {:geometry, _} -> true
      {:geography, _} -> true
      # Ecto.Enum is built-in
      {:enum, _} -> false
      _ -> false
    end
  end
end
