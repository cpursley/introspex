defmodule Mix.Tasks.Ecto.Gen.Schema do
  @shortdoc "Generates Ecto schemas from an existing PostgreSQL database"
  @moduledoc """
  Generates Ecto schemas from an existing PostgreSQL database.

  This task introspects your PostgreSQL database and generates Ecto schema
  files with proper field types, associations, and changesets.

  ## Examples

      $ mix ecto.gen.schema --repo MyApp.Repo
      $ mix ecto.gen.schema --repo MyApp.Repo --schema public --table users
      $ mix ecto.gen.schema --repo MyApp.Repo --exclude-views
      $ mix ecto.gen.schema --repo MyApp.Repo --binary-id --dry-run

  ## Options

    * `--repo` - the repository module (required)
    * `--schema` - PostgreSQL schema name (default: "public")
    * `--table` - generate schema for a specific table only
    * `--exclude-views` - skip generating schemas for views and materialized views
    * `--binary-id` - use binary_id (UUID) for primary keys
    * `--no-timestamps` - do not generate timestamps() in schemas
    * `--no-changesets` - skip generating changeset functions
    * `--no-associations` - skip detecting and generating associations
    * `--module-prefix` - prefix for generated module names (default: app name)
    * `--output-dir` - output directory for schema files (default: lib/app_name)
    * `--dry-run` - preview what would be generated without writing files

  """

  use Mix.Task

  alias Introspex.Postgres.{Introspector, RelationshipAnalyzer}
  alias Introspex.SchemaBuilder

  @switches [
    repo: :string,
    schema: :string,
    table: :string,
    exclude_views: :boolean,
    binary_id: :boolean,
    no_timestamps: :boolean,
    no_changesets: :boolean,
    no_associations: :boolean,
    module_prefix: :string,
    output_dir: :string,
    dry_run: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _} = OptionParser.parse!(args, switches: @switches)

    repo = get_repo!(opts)
    ensure_repo_started!(repo)

    schema = Keyword.get(opts, :schema, "public")
    specific_table = Keyword.get(opts, :table)
    exclude_views = Keyword.get(opts, :exclude_views, false)
    dry_run = Keyword.get(opts, :dry_run, false)

    Mix.shell().info("Introspecting PostgreSQL database...")

    tables =
      case Introspector.list_tables(repo, schema, exclude_views) do
        {:error, error} ->
          Mix.raise("Failed to list tables: #{inspect(error)}")

        tables when specific_table != nil ->
          Enum.filter(tables, &(&1.name == specific_table))

        tables ->
          tables
      end

    if Enum.empty?(tables) do
      Mix.shell().info("No tables found to generate schemas for.")
    else
      Mix.shell().info("Found #{length(tables)} table(s) to process.")

      # Generate schemas for each table
      Enum.each(tables, fn table_info ->
        generate_schema_for_table(repo, table_info, tables, schema, opts, dry_run)
      end)

      if dry_run do
        Mix.shell().info("\nDry run complete. No files were written.")
      else
        Mix.shell().info("\nSchema generation complete!")
      end
    end
  end

  defp generate_schema_for_table(repo, table_info, all_tables, db_schema, opts, dry_run) do
    Mix.shell().info("\nProcessing #{table_info.type}: #{table_info.name}")

    # Get table metadata
    columns = Introspector.get_columns(repo, table_info.name, db_schema)
    primary_keys = Introspector.get_primary_keys(repo, table_info.name, db_schema)

    # Get relationships unless disabled
    relationships =
      if Keyword.get(opts, :no_associations, false) or table_info.type != :table do
        %{belongs_to: [], has_many: [], has_one: [], many_to_many: []}
      else
        RelationshipAnalyzer.analyze_relationships(repo, table_info.name, all_tables, db_schema)
      end

    # Get constraints
    unique_constraints =
      if table_info.type == :table do
        Introspector.get_unique_constraints(repo, table_info.name, db_schema)
      else
        []
      end

    check_constraints =
      if table_info.type == :table do
        Introspector.get_check_constraints(repo, table_info.name, db_schema)
      else
        []
      end

    # Build the schema
    module_name = build_module_name(table_info.name, opts)

    table_data = %{
      table: table_info,
      columns: columns,
      primary_keys: primary_keys,
      relationships: relationships,
      unique_constraints: unique_constraints,
      check_constraints: check_constraints,
      table_type: table_info.type
    }

    builder_opts = [
      binary_id: Keyword.get(opts, :binary_id, false),
      skip_timestamps: Keyword.get(opts, :no_timestamps, false),
      skip_changesets: Keyword.get(opts, :no_changesets, false),
      app_name: get_app_name(opts)
    ]

    schema_content = SchemaBuilder.build_schema(table_data, module_name, builder_opts)

    # Write or display the schema
    if dry_run do
      Mix.shell().info("\n--- #{module_name} ---")
      Mix.shell().info(schema_content)
    else
      write_schema_file(module_name, schema_content, opts)
    end
  end

  defp get_repo!(opts) do
    case Keyword.get(opts, :repo) do
      nil ->
        Mix.raise("--repo option is required. Example: --repo MyApp.Repo")

      repo_string ->
        Module.concat([repo_string])
    end
  end

  defp ensure_repo_started!(repo) do
    case Code.ensure_compiled(repo) do
      {:module, _} ->
        if function_exported?(repo, :__adapter__, 0) do
          {:ok, _} = Application.ensure_all_started(:postgrex)

          case repo.start_link() do
            {:ok, _} -> :ok
            {:error, {:already_started, _}} -> :ok
            {:error, error} -> Mix.raise("Failed to start repo: #{inspect(error)}")
          end
        else
          Mix.raise("#{inspect(repo)} is not an Ecto.Repo")
        end

      {:error, error} ->
        Mix.raise("Could not load #{inspect(repo)}: #{inspect(error)}")
    end
  end

  defp build_module_name(table_name, opts) do
    prefix = Keyword.get(opts, :module_prefix, get_app_name(opts))

    module_parts = [prefix] ++ [Macro.camelize(table_name)]
    Enum.join(module_parts, ".")
  end

  defp get_app_name(opts) do
    Keyword.get(opts, :module_prefix) ||
      Mix.Project.config()[:app]
      |> to_string()
      |> Macro.camelize()
  end

  defp write_schema_file(module_name, content, opts) do
    # Determine output path
    app_name = get_app_name(opts) |> Macro.underscore()
    output_dir = Keyword.get(opts, :output_dir, "lib/#{app_name}")

    # Convert module name to file path
    file_name =
      module_name
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    file_path = Path.join(output_dir, "#{file_name}.ex")

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Write the file
    File.write!(file_path, content)
    Mix.shell().info("Created #{file_path}")
  end
end
