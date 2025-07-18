defmodule Introspex.SchemaBuilder do
  @moduledoc """
  Builds Ecto schema definitions from database introspection data.
  """

  alias Introspex.Postgres.TypeMapper

  @doc """
  Builds a complete schema module from table metadata.
  """
  def build_schema(table_info, module_name, opts \\ []) do
    %{
      table: table,
      columns: columns,
      primary_keys: primary_keys,
      relationships: relationships,
      unique_constraints: unique_constraints,
      check_constraints: _check_constraints,
      table_type: table_type
    } = table_info

    binary_id = Keyword.get(opts, :binary_id, false)
    skip_timestamps = Keyword.get(opts, :skip_timestamps, false)
    _app_name = Keyword.get(opts, :app_name, "MyApp")
    module_prefix = Keyword.get(opts, :module_prefix)

    # Auto-detect if primary key is UUID
    primary_key_info = detect_primary_key_type(columns, primary_keys)
    binary_id = binary_id || primary_key_info.is_uuid

    # Check if we have PostGIS types
    has_postgis =
      Enum.any?(columns, fn col ->
        TypeMapper.requires_special_import?(
          TypeMapper.map_type(col.data_type, nil, default: col.default)
        )
      end)

    # Detect if we can use Ecto's timestamps() macro
    has_timestamps = TypeMapper.ecto_timestamps_compatible?(columns) and not skip_timestamps

    # Filter out timestamp fields if using timestamps() macro
    schema_fields =
      if has_timestamps do
        Enum.reject(columns, &TypeMapper.ecto_timestamp_field?(&1.name))
      else
        columns
      end

    # Filter out foreign key fields that will be handled by belongs_to
    foreign_key_fields =
      if relationships && Map.get(relationships, :belongs_to) do
        relationships.belongs_to
        |> Enum.map(& &1.foreign_key)
        |> Enum.map(&to_string/1)
      else
        []
      end

    filtered_schema_fields = Enum.reject(schema_fields, &(&1.name in foreign_key_fields))

    # Build the module
    schema_definition =
      build_schema_definition(%{
        table_name: table.name,
        fields: filtered_schema_fields,
        primary_keys: primary_keys,
        relationships: relationships,
        binary_id: binary_id,
        has_timestamps: has_timestamps,
        table_type: table_type,
        primary_key_info: primary_key_info,
        module_prefix: module_prefix,
        columns: columns
      })

    changeset_definition =
      if table_type == :table do
        build_changeset_function(schema_fields, unique_constraints, relationships)
      else
        nil
      end

    build_module(
      module_name,
      schema_definition,
      changeset_definition,
      has_postgis,
      table_type,
      table.comment
    )
  end

  defp build_module(
         module_name,
         schema_definition,
         changeset_definition,
         has_postgis,
         table_type,
         comment
       ) do
    imports = build_imports(changeset_definition != nil, has_postgis)

    comment_doc =
      if comment do
        "@moduledoc \"\"\"\n  #{comment}\n  \"\"\""
      else
        case table_type do
          :view -> "@moduledoc \"Schema for database view\""
          :materialized_view -> "@moduledoc \"Schema for materialized view\""
          _ -> "@moduledoc false"
        end
      end

    """
    defmodule #{module_name} do
      #{comment_doc}
      use Ecto.Schema
      #{imports}

      #{schema_definition}
      #{if changeset_definition, do: "\n" <> changeset_definition, else: ""}
    end
    """
  end

  defp build_imports(has_changeset, _has_postgis) do
    imports = []
    imports = if has_changeset, do: ["import Ecto.Changeset" | imports], else: imports

    # If we have PostGIS types, we don't need to alias - just use the full module names
    # This avoids any confusion about which types are available

    if length(imports) > 0 do
      Enum.join(imports, "\n  ")
    else
      ""
    end
  end

  defp build_schema_definition(%{
         table_name: table_name,
         fields: fields,
         primary_keys: primary_keys,
         relationships: relationships,
         binary_id: binary_id,
         has_timestamps: has_timestamps,
         table_type: table_type,
         primary_key_info: primary_key_info,
         module_prefix: module_prefix,
         columns: columns
       }) do
    primary_key_config = build_primary_key_config(primary_keys, binary_id, primary_key_info)

    field_definitions =
      fields
      |> Enum.map(&build_field_definition/1)
      |> Enum.reject(&is_nil/1)

    association_definitions =
      if table_type == :table do
        build_association_definitions(relationships, module_prefix, columns, binary_id)
      else
        []
      end

    timestamp_definition = if has_timestamps, do: ["timestamps()"], else: []

    all_definitions = field_definitions ++ association_definitions ++ timestamp_definition

    """
    #{primary_key_config}
      #{if table_type == :table, do: "schema \"#{table_name}\" do", else: "# This is a #{table_type} - queries will work but inserts/updates/deletes are not supported\n      schema \"#{table_name}\" do"}
        #{Enum.join(all_definitions, "\n    ")}
      end
    """
  end

  defp detect_primary_key_type(columns, primary_keys) do
    case primary_keys do
      [pk_name] ->
        pk_column = Enum.find(columns, &(&1.name == pk_name))

        if pk_column do
          is_uuid = pk_column.data_type in ["uuid", "UUID"]
          has_db_default = pk_column.default && String.contains?(pk_column.default, "uuid")

          %{
            name: pk_name,
            is_uuid: is_uuid,
            has_db_default: has_db_default
          }
        else
          %{name: pk_name, is_uuid: false, has_db_default: false}
        end

      _ ->
        %{name: nil, is_uuid: false, has_db_default: false}
    end
  end

  defp build_primary_key_config([], _binary_id, _pk_info) do
    "@primary_key false"
  end

  defp build_primary_key_config([single_pk], binary_id, pk_info) when single_pk == "id" do
    if binary_id do
      if pk_info.has_db_default do
        "@primary_key {:id, :binary_id, autogenerate: false}\n  @foreign_key_type :binary_id\n"
      else
        "@primary_key {:id, :binary_id, autogenerate: true}\n  @foreign_key_type :binary_id\n"
      end
    else
      ""
    end
  end

  defp build_primary_key_config(primary_keys, _binary_id, _pk_info)
       when length(primary_keys) > 1 do
    # Composite primary key
    "@primary_key false"
  end

  defp build_primary_key_config([single_pk], binary_id, pk_info) do
    # Non-standard primary key name
    if binary_id && pk_info.is_uuid do
      if pk_info.has_db_default do
        "@primary_key {:#{single_pk}, :binary_id, autogenerate: false}"
      else
        "@primary_key {:#{single_pk}, :binary_id, autogenerate: true}"
      end
    else
      "@primary_key {:#{single_pk}, :id, autogenerate: true}"
    end
  end

  defp build_field_definition(column) do
    %{
      name: name,
      data_type: data_type,
      not_null: _not_null,
      default: default,
      comment: _comment,
      enum_values: enum_values
    } = column

    type = TypeMapper.map_type(data_type, enum_values, default: default)

    # Don't add primary key fields if they're named "id"
    if name == "id" do
      nil
    else
      case type do
        :json_requires_manual_type ->
          """
          # JSON field - requires manual type specification:
          # field :#{name}, :map                    # For JSON objects
          """

        :jsonb_requires_manual_type ->
          """
          # JSONB field - requires manual type specification based on your data:
          # field :#{name}, :map                    # For JSON objects: {"key": "value"}
          # field :#{name}, {:array, :string}       # For string arrays: ["value1", "value2"]
          # field :#{name}, {:array, :integer}      # For integer arrays: [1, 2, 3]
          # field :#{name}, {:array, :map}          # For object arrays: [{"id": 1}, {"id": 2}]
          """

        _ ->
          type_string = TypeMapper.type_to_string(type)
          opts = []

          # Let PostgreSQL handle all defaults - don't include them in Ecto schema
          # This prevents conflicts and ensures database defaults work as intended

          if length(opts) > 0 do
            "field :#{name}, #{type_string}, #{Enum.join(opts, ", ")}"
          else
            "field :#{name}, #{type_string}"
          end
      end
    end
  end

  defp build_association_definitions(relationships, module_prefix, columns, binary_id) do
    belongs_to =
      Enum.map(
        Map.get(relationships, :belongs_to, []),
        &build_belongs_to(&1, module_prefix, columns, binary_id)
      )

    has_many = Enum.map(Map.get(relationships, :has_many, []), &build_has_many(&1, module_prefix))
    has_one = Enum.map(Map.get(relationships, :has_one, []), &build_has_one(&1, module_prefix))

    many_to_many =
      Enum.map(Map.get(relationships, :many_to_many, []), &build_many_to_many(&1, module_prefix))

    belongs_to ++ has_many ++ has_one ++ many_to_many
  end

  defp build_belongs_to(assoc, module_prefix, columns, binary_id) do
    opts = []

    opts =
      if assoc.foreign_key != String.to_atom(to_string(assoc.field) <> "_id"),
        do: ["foreign_key: :#{assoc.foreign_key}" | opts],
        else: opts

    opts = if assoc.references != :id, do: ["references: :#{assoc.references}" | opts], else: opts

    # Check if we need to specify the type based on the foreign key column type
    fk_column = Enum.find(columns, &(&1.name == to_string(assoc.foreign_key)))

    opts =
      if binary_id && fk_column &&
           fk_column.data_type in ["integer", "bigint", "int4", "int8", "smallint", "int2"] do
        ["type: :id" | opts]
      else
        if Map.get(assoc, :type), do: ["type: :#{assoc.type}" | opts], else: opts
      end

    module_name =
      if Map.get(assoc, :module),
        do: assoc.module,
        else: table_to_module(assoc.table, module_prefix)

    if length(opts) > 0 do
      "belongs_to :#{assoc.field}, #{module_name}, #{Enum.join(opts, ", ")}"
    else
      "belongs_to :#{assoc.field}, #{module_name}"
    end
  end

  defp build_has_many(assoc, module_prefix) do
    module_name = table_to_module(assoc.table, module_prefix)
    "has_many :#{assoc.field}, #{module_name}, foreign_key: :#{assoc.foreign_key}"
  end

  defp build_has_one(assoc, module_prefix) do
    module_name = table_to_module(assoc.table, module_prefix)
    "has_one :#{assoc.field}, #{module_name}, foreign_key: :#{assoc.foreign_key}"
  end

  defp build_many_to_many(assoc, module_prefix) do
    module_name = table_to_module(assoc.table, module_prefix)
    "many_to_many :#{assoc.field}, #{module_name}, join_through: \"#{assoc.join_through}\""
  end

  defp build_changeset_function(fields, unique_constraints, relationships) do
    cast_fields =
      fields
      |> Enum.reject(&(&1.name == "id"))
      |> Enum.map(&String.to_atom(&1.name))

    # Add foreign key fields from belongs_to relationships
    belongs_to_fields =
      relationships.belongs_to
      |> Enum.map(& &1.foreign_key)

    all_cast_fields = (cast_fields ++ belongs_to_fields) |> Enum.uniq()

    required_fields =
      fields
      |> Enum.filter(&(&1.not_null && &1.name != "id" && is_nil(&1.default)))
      |> Enum.map(&String.to_atom(&1.name))

    """
      @doc false
      def changeset(#{String.downcase(get_struct_name())}, attrs) do
        #{String.downcase(get_struct_name())}
        |> cast(attrs, #{inspect(all_cast_fields, limit: :infinity)})
        #{if length(required_fields) > 0, do: "|> validate_required(#{inspect(required_fields, limit: :infinity)})", else: ""}
        #{build_validations(fields)}
        #{build_unique_constraints(unique_constraints)}
        #{build_foreign_key_constraints(relationships.belongs_to)}
      end
    """
  end

  defp build_validations(fields) do
    fields
    |> Enum.map(&build_field_validation/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n    ")
  end

  defp build_field_validation(field) do
    cond do
      field.data_type in ["integer", "bigint", "smallint"] ->
        # TODO: Parse check constraints for number validations
        nil

      true ->
        nil
    end
  end

  defp build_unique_constraints(constraints) do
    constraints
    |> Enum.map(fn constraint ->
      # Use the first column if it's a single column constraint
      if length(constraint.columns) == 1 do
        "|> unique_constraint(:#{hd(constraint.columns)})"
      else
        "|> unique_constraint(#{inspect(Enum.map(constraint.columns, &String.to_atom/1), limit: :infinity)}, name: :#{constraint.constraint_name})"
      end
    end)
    |> Enum.join("\n    ")
  end

  defp build_foreign_key_constraints(belongs_to_assocs) do
    belongs_to_assocs
    |> Enum.map(fn assoc ->
      "|> foreign_key_constraint(:#{assoc.foreign_key})"
    end)
    |> Enum.join("\n    ")
  end

  defp table_to_module(table_name, module_prefix) do
    # If module_prefix is provided, prepend it to the module name
    if module_prefix do
      "#{module_prefix}.#{Macro.camelize(table_name)}"
    else
      Macro.camelize(table_name)
    end
  end

  defp get_struct_name do
    # Extract the last part of the module name for the struct variable
    # This is a simplified version - in production, pass this from the module name
    "schema"
  end
end
