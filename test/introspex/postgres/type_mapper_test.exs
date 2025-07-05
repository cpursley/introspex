defmodule Introspex.Postgres.TypeMapperTest do
  use ExUnit.Case, async: true

  alias Introspex.Postgres.TypeMapper

  describe "map_type/2" do
    test "maps integer types correctly" do
      assert TypeMapper.map_type("integer") == :integer
      assert TypeMapper.map_type("bigint") == :integer
      assert TypeMapper.map_type("smallint") == :integer
      assert TypeMapper.map_type("serial") == :integer
    end

    test "maps decimal and float types correctly" do
      assert TypeMapper.map_type("decimal") == :decimal
      assert TypeMapper.map_type("numeric") == :decimal
      assert TypeMapper.map_type("real") == :float
      assert TypeMapper.map_type("double precision") == :float
      assert TypeMapper.map_type("money") == :decimal
    end

    test "maps string types correctly" do
      assert TypeMapper.map_type("character varying") == :string
      assert TypeMapper.map_type("varchar") == :string
      assert TypeMapper.map_type("text") == :string
      assert TypeMapper.map_type("citext") == :string
    end

    test "maps UUID type correctly" do
      assert TypeMapper.map_type("uuid") == :binary_id
    end

    test "maps boolean types correctly" do
      assert TypeMapper.map_type("boolean") == :boolean
      assert TypeMapper.map_type("bool") == :boolean
    end

    test "maps date/time types correctly" do
      assert TypeMapper.map_type("timestamp") == :naive_datetime
      assert TypeMapper.map_type("timestamp without time zone") == :naive_datetime
      assert TypeMapper.map_type("timestamp with time zone") == :utc_datetime
      assert TypeMapper.map_type("timestamptz") == :utc_datetime
      assert TypeMapper.map_type("date") == :date
      assert TypeMapper.map_type("time") == :time
    end

    test "maps JSON types to special markers" do
      assert TypeMapper.map_type("json") == :json_requires_manual_type
      assert TypeMapper.map_type("jsonb") == :jsonb_requires_manual_type
    end

    test "maps array types correctly" do
      assert TypeMapper.map_type("integer[]") == {:array, :integer}
      assert TypeMapper.map_type("text[]") == {:array, :string}
      assert TypeMapper.map_type("boolean[]") == {:array, :boolean}
    end

    test "maps enum types correctly" do
      enum_values = ["active", "inactive", "pending"]

      assert TypeMapper.map_type("user-defined", enum_values) ==
               {:enum, [:active, :inactive, :pending]}
    end

    test "maps PostGIS types correctly" do
      assert TypeMapper.map_type("geometry") == {:geometry, "Geometry"}
      assert TypeMapper.map_type("geography") == {:geography, "Geography"}
      assert TypeMapper.map_type("point") == {:geometry, "Point"}
    end

    test "maps JSONB to special marker for manual intervention" do
      # All JSONB fields map to special marker regardless of defaults or field names
      assert TypeMapper.map_type("jsonb", nil, default: "jsonb_build_array()") ==
               :jsonb_requires_manual_type

      assert TypeMapper.map_type("jsonb", nil, default: "'[]'::jsonb") ==
               :jsonb_requires_manual_type

      assert TypeMapper.map_type("jsonb", nil, default: "array_to_json(ARRAY[]::text[])") ==
               :jsonb_requires_manual_type

      assert TypeMapper.map_type("jsonb", nil, default: "'{}'::jsonb") ==
               :jsonb_requires_manual_type

      assert TypeMapper.map_type("jsonb", nil, default: nil) == :jsonb_requires_manual_type
      assert TypeMapper.map_type("jsonb") == :jsonb_requires_manual_type

      # Field names don't affect the type
      assert TypeMapper.map_type("jsonb", nil,
               default: "jsonb_build_array()",
               field_name: "tag_ids"
             ) == :jsonb_requires_manual_type

      assert TypeMapper.map_type("jsonb", nil,
               default: "jsonb_build_array()",
               field_name: "items"
             ) == :jsonb_requires_manual_type
    end

    test "falls back to string for unknown types" do
      assert TypeMapper.map_type("unknown_type") == :string
    end
  end

  describe "type_to_string/1" do
    test "converts simple types to string" do
      assert TypeMapper.type_to_string(:integer) == ":integer"
      assert TypeMapper.type_to_string(:string) == ":string"
      assert TypeMapper.type_to_string(:binary_id) == ":binary_id"
    end

    test "converts array types to string" do
      assert TypeMapper.type_to_string({:array, :integer}) == "{:array, :integer}"
      assert TypeMapper.type_to_string({:array, :string}) == "{:array, :string}"
    end

    test "converts enum types to string" do
      assert TypeMapper.type_to_string({:enum, [:active, :inactive]}) ==
               "Ecto.Enum, values: [:active, :inactive]"
    end

    test "converts PostGIS types to string" do
      assert TypeMapper.type_to_string({:geometry, "Point"}) == "Geo.PostGIS.Geometry"
      assert TypeMapper.type_to_string({:geography, "Polygon"}) == "Geo.PostGIS.Geometry"
    end
  end

  describe "ecto_timestamp_field?/1" do
    test "identifies Ecto timestamp fields" do
      assert TypeMapper.ecto_timestamp_field?("inserted_at") == true
      assert TypeMapper.ecto_timestamp_field?("updated_at") == true
    end

    test "returns false for non-Ecto timestamp fields" do
      assert TypeMapper.ecto_timestamp_field?("created_at") == false
      assert TypeMapper.ecto_timestamp_field?("modified_at") == false
      assert TypeMapper.ecto_timestamp_field?("name") == false
      assert TypeMapper.ecto_timestamp_field?("id") == false
      assert TypeMapper.ecto_timestamp_field?("email") == false
    end
  end

  describe "ecto_timestamps_compatible?/1" do
    test "returns true when both inserted_at and updated_at exist with timestamp types" do
      columns = [
        %{name: "id", data_type: "integer"},
        %{name: "inserted_at", data_type: "timestamp"},
        %{name: "updated_at", data_type: "timestamp"}
      ]

      assert TypeMapper.ecto_timestamps_compatible?(columns) == true
    end

    test "returns true with timestamptz types" do
      columns = [
        %{name: "inserted_at", data_type: "timestamptz"},
        %{name: "updated_at", data_type: "timestamp with time zone"}
      ]

      assert TypeMapper.ecto_timestamps_compatible?(columns) == true
    end

    test "returns false when only one timestamp field exists" do
      columns = [
        %{name: "id", data_type: "integer"},
        %{name: "inserted_at", data_type: "timestamp"}
      ]

      assert TypeMapper.ecto_timestamps_compatible?(columns) == false
    end

    test "returns false when timestamp fields have wrong types" do
      columns = [
        %{name: "inserted_at", data_type: "date"},
        %{name: "updated_at", data_type: "timestamp"}
      ]

      assert TypeMapper.ecto_timestamps_compatible?(columns) == false
    end

    test "returns false when using non-standard timestamp names" do
      columns = [
        %{name: "created_at", data_type: "timestamp"},
        %{name: "updated_at", data_type: "timestamp"}
      ]

      assert TypeMapper.ecto_timestamps_compatible?(columns) == false
    end
  end

  describe "requires_special_import?/1" do
    test "returns true for PostGIS types" do
      assert TypeMapper.requires_special_import?({:geometry, "Point"}) == true
      assert TypeMapper.requires_special_import?({:geography, "Polygon"}) == true
    end

    test "returns false for regular types" do
      assert TypeMapper.requires_special_import?(:string) == false
      assert TypeMapper.requires_special_import?({:enum, [:active]}) == false
      assert TypeMapper.requires_special_import?({:array, :integer}) == false
    end
  end
end
