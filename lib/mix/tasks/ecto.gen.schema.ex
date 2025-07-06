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
      $ mix ecto.gen.schema --repo MyApp.Repo --context Accounts --context-tables users,profiles
      $ mix ecto.gen.schema --repo MyApp.Repo --context Blog --context-tables posts,comments,tags

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
    * `--context` - Phoenix context name for organizing related schemas
    * `--context-tables` - comma-separated list of tables to include in the context (only these tables will be generated)
    * `--path` - custom path segment(s) to insert in the output directory (e.g., "queries" results in lib/app_name/queries/...)

  """

  use Mix.Task

  alias Introspex.Postgres.{Introspector, RelationshipAnalyzer}
  alias Introspex.{SchemaBuilder, ContextBuilder}

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
    dry_run: :boolean,
    context: :string,
    context_tables: :string,
    path: :string
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
          # If context-tables is specified, only process those tables
          context_tables = parse_context_tables(opts)

          if context_tables != [] do
            Enum.filter(tables, &(&1.name in context_tables))
          else
            tables
          end
      end

    if Enum.empty?(tables) do
      Mix.shell().info("No tables found to generate schemas for.")
    else
      Mix.shell().info("Found #{length(tables)} table(s) to process.")

      # Generate schemas for each table
      context_schemas =
        Enum.map(tables, fn table_info ->
          generate_schema_for_table(repo, table_info, tables, schema, opts, dry_run)
        end)

      # Generate context module if context is specified
      if Keyword.get(opts, :context) && !dry_run do
        generate_context_module(opts, context_schemas)
      end

      if dry_run do
        Mix.shell().info("\nDry run complete. No files were written.")
      else
        Mix.shell().info("\nSchema generation complete!")
      end
    end
  end

  # Generates a schema file for a single database table
  defp generate_schema_for_table(repo, table_info, all_tables, db_schema, opts, dry_run) do
    Mix.shell().info("\nProcessing #{table_info.type}: #{table_info.name}")

    # Filter context options to only include the current table if it's in the context
    table_opts =
      if should_include_in_context?(table_info.name, opts) do
        opts
      else
        Keyword.drop(opts, [:context])
      end

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
    module_name = build_module_name(table_info.name, table_opts)

    table_data = %{
      table: table_info,
      columns: columns,
      primary_keys: primary_keys,
      relationships: relationships,
      unique_constraints: unique_constraints,
      check_constraints: check_constraints,
      table_type: table_info.type
    }

    # Calculate module prefix for associations
    context = Keyword.get(opts, :context)

    module_prefix =
      if context && table_info.name in parse_context_tables(opts) do
        # Remove the table name from the end to get the prefix
        module_name
        |> String.split(".")
        |> List.delete_at(-1)
        |> Enum.join(".")
      else
        # For non-context tables, use the app name + path
        module_name
        |> String.split(".")
        |> List.delete_at(-1)
        |> Enum.join(".")
      end

    builder_opts = [
      binary_id: Keyword.get(opts, :binary_id, false),
      skip_timestamps: Keyword.get(opts, :no_timestamps, false),
      skip_changesets: Keyword.get(opts, :no_changesets, false),
      app_name: get_app_name(opts),
      module_prefix: module_prefix
    ]

    schema_content = SchemaBuilder.build_schema(table_data, module_name, builder_opts)

    # Write or display the schema
    if dry_run do
      Mix.shell().info("\n--- #{module_name} ---")
      Mix.shell().info(schema_content)
    else
      write_schema_file(module_name, schema_content, table_opts)
    end

    # Return schema info for context generation
    %{
      module_name: String.split(module_name, ".") |> List.last(),
      singular_name: singularize(table_info.name),
      plural_name: Macro.underscore(table_info.name),
      table_name: table_info.name,
      table_type: table_info.type
    }
  end

  # Extracts and validates the repository module from options
  defp get_repo!(opts) do
    case Keyword.get(opts, :repo) do
      nil ->
        Mix.raise("--repo option is required. Example: --repo MyApp.Repo")

      repo_string ->
        Module.concat([repo_string])
    end
  end

  # Ensures the repository is compiled and started
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

  # Builds the full module name including app prefix, path segments, and context
  defp build_module_name(table_name, opts) do
    prefix = Keyword.get(opts, :module_prefix, get_app_name(opts))
    context = Keyword.get(opts, :context)
    context_tables = parse_context_tables(opts)
    custom_path = Keyword.get(opts, :path)

    # Build module parts starting with prefix
    base_parts = [prefix]

    # Add path segments if provided
    base_parts =
      if custom_path do
        path_parts =
          custom_path
          |> String.split("/", trim: true)
          |> Enum.map(&Macro.camelize/1)

        base_parts ++ path_parts
      else
        base_parts
      end

    # Add context and table name
    module_parts =
      if context && table_name in context_tables do
        base_parts ++ [context, Macro.camelize(table_name)]
      else
        base_parts ++ [Macro.camelize(table_name)]
      end

    Enum.join(module_parts, ".")
  end

  # Gets the application name from options or Mix project config
  defp get_app_name(opts) do
    Keyword.get(opts, :module_prefix) ||
      Mix.Project.config()[:app]
      |> to_string()
      |> Macro.camelize()
  end

  # Parses the comma-separated list of context tables from options
  defp parse_context_tables(opts) do
    case Keyword.get(opts, :context_tables) do
      nil ->
        []

      tables_string ->
        tables_string
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
    end
  end

  # Determines if a table should be included in the context based on options
  defp should_include_in_context?(table_name, opts) do
    context = Keyword.get(opts, :context)
    context_tables = parse_context_tables(opts)

    context != nil && (context_tables == [] || table_name in context_tables)
  end

  # Writes the generated schema content to the appropriate file path
  defp write_schema_file(module_name, content, opts) do
    # Determine output path
    app_name = get_app_name(opts) |> Macro.underscore()
    output_dir = Keyword.get(opts, :output_dir, "lib/#{app_name}")

    # Convert module name to file path
    module_parts = String.split(module_name, ".")

    # Skip the app prefix to get the relative path
    [_app_prefix | relative_parts] = module_parts

    # Convert each part to underscore and build the file path
    relative_path_parts = Enum.map(relative_parts, &Macro.underscore/1)
    file_name = List.last(relative_path_parts)
    directory_parts = List.delete_at(relative_path_parts, -1)

    # Build the full file path
    full_path_parts = [output_dir] ++ directory_parts
    file_path = Path.join(full_path_parts ++ ["#{file_name}.ex"])

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(file_path))

    # Write the file
    File.write!(file_path, content)
    Mix.shell().info("Created #{file_path}")
  end

  # Generates the Phoenix context module file if --context option is provided
  defp generate_context_module(opts, schemas) do
    context = Keyword.get(opts, :context)

    if context do
      # Filter out nil schemas from dry run
      schemas = Enum.reject(schemas, &is_nil/1)

      context_content =
        ContextBuilder.build_context(
          context,
          schemas,
          app_name: get_app_name(opts),
          repo_module: Keyword.get(opts, :repo) |> to_string(),
          path: Keyword.get(opts, :path)
        )

      # Write context file
      app_name = get_app_name(opts) |> Macro.underscore()
      output_dir = Keyword.get(opts, :output_dir, "lib/#{app_name}")
      custom_path = Keyword.get(opts, :path)

      path_parts =
        [output_dir] ++
          if custom_path, do: String.split(custom_path, "/", trim: true), else: []

      context_file_path = Path.join(path_parts ++ ["#{Macro.underscore(context)}.ex"])

      File.mkdir_p!(Path.dirname(context_file_path))
      File.write!(context_file_path, context_content)
      Mix.shell().info("Created #{context_file_path}")
    end
  end

  # Simple singularization of table names for generating singular resource names
  defp singularize(table_name) do
    # Simple singularization - can be improved with a proper inflector
    name = Macro.underscore(table_name)

    cond do
      String.ends_with?(name, "ies") -> String.replace_suffix(name, "ies", "y")
      String.ends_with?(name, "ses") -> String.replace_suffix(name, "ses", "s")
      String.ends_with?(name, "ches") -> String.replace_suffix(name, "ches", "ch")
      String.ends_with?(name, "xes") -> String.replace_suffix(name, "xes", "x")
      String.ends_with?(name, "s") -> String.replace_suffix(name, "s", "")
      true -> name
    end
  end
end
