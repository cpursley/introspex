defmodule Introspex.ContextBuilder do
  @moduledoc """
  Generates Phoenix context modules with CRUD functions for database tables.

  Context modules provide a boundary layer between your web interface and data layer,
  organizing related functionality together. This module generates context files that
  include standard CRUD operations, with special handling for views that only get
  read operations.
  """

  @doc """
  Builds a Phoenix context module with CRUD functions for the given schemas.

  ## Parameters

    * `context_name` - The name of the context (e.g., "Accounts", "Blog")
    * `schemas` - List of schema information maps containing:
      * `:module_name` - The schema module name
      * `:singular_name` - Singular form of the resource name
      * `:plural_name` - Plural form of the resource name
      * `:table_type` - Type of database object (:table, :view, or :materialized_view)
    * `opts` - Keyword list of options:
      * `:app_name` - The application name
      * `:repo_module` - The Repo module name
      * `:path` - Optional path segments to include in module name

  ## Examples

      build_context("Accounts", schemas, app_name: "MyApp", repo_module: "MyApp.Repo")

  Returns a string containing the complete context module code.
  """
  def build_context(context_name, schemas, opts) do
    app_name = Keyword.get(opts, :app_name)
    repo_module = Keyword.get(opts, :repo_module, "#{app_name}.Repo")
    path = Keyword.get(opts, :path)

    # Build full module name with path
    base_parts = [app_name]

    base_parts =
      if path do
        path_parts =
          path
          |> String.split("/", trim: true)
          |> Enum.map(&Macro.camelize/1)

        base_parts ++ path_parts
      else
        base_parts
      end

    full_module_parts = base_parts ++ [context_name]
    full_module_name = Enum.join(full_module_parts, ".")

    # Generate functions for each schema - only read operations for views
    # Track function names to avoid duplicates and which schemas are used
    {functions, _, used_schemas} =
      Enum.reduce(schemas, {[], MapSet.new(), []}, fn schema,
                                                      {funcs, used_names, used_schemas_acc} ->
        singular = schema.singular_name
        plural = schema.plural_name
        module = schema.module_name
        is_view = Map.get(schema, :table_type) in [:view, :materialized_view]

        # If we've already used this function name, skip it
        if MapSet.member?(used_names, singular) do
          {funcs, used_names, used_schemas_acc}
        else
          base_functions = [
            generate_list_function(plural, module),
            generate_get_function(singular, module)
          ]

          all_functions =
            if is_view do
              # Views only get read operations
              base_functions
            else
              # Tables get full CRUD operations
              base_functions ++
                [
                  generate_create_function(singular, module),
                  generate_update_function(singular, module),
                  generate_delete_function(singular, module),
                  generate_change_function(singular, module)
                ]
            end

          {[all_functions | funcs], MapSet.put(used_names, singular), [module | used_schemas_acc]}
        end
      end)

    functions = List.flatten(Enum.reverse(functions))
    used_schemas = Enum.uniq(Enum.reverse(used_schemas))

    # Build alias block only for schemas that are actually used
    alias_block =
      if length(used_schemas) == 0 do
        ""
      else
        if length(used_schemas) == 1 do
          "  alias #{full_module_name}.#{List.first(used_schemas)}"
        else
          "  alias #{full_module_name}\n\n" <>
            "  alias #{context_name}.{\n" <>
            Enum.map_join(used_schemas, ",\n", fn module ->
              "    #{module}"
            end) <>
            "\n  }"
        end
      end

    # Build the complete module
    "defmodule #{full_module_name} do\n" <>
      "  @moduledoc \"The #{context_name} context.\"\n\n" <>
      "  import Ecto.Query, warn: false\n" <>
      "  alias #{repo_module}\n" <>
      if(alias_block != "", do: "\n" <> alias_block <> "\n", else: "") <>
      "\n" <>
      Enum.join(functions, "\n\n") <> "\nend\n"
  end

  defp generate_list_function(plural_name, module_name) do
    "  @doc \"\"\"\n" <>
      "  Returns the list of #{plural_name}.\n" <>
      "\n" <>
      "  ## Examples\n" <>
      "\n" <>
      "      iex> list_#{plural_name}()\n" <>
      "      [%#{module_name}{}, ...]\n" <>
      "\n" <>
      "  \"\"\"\n" <>
      "  def list_#{plural_name} do\n" <>
      "    Repo.all(#{module_name})\n" <>
      "  end"
  end

  defp generate_get_function(singular_name, module_name) do
    "  @doc \"\"\"\n" <>
      "  Gets a single #{singular_name}.\n" <>
      "\n" <>
      "  Raises `Ecto.NoResultsError` if the #{String.replace(singular_name, "_", " ")} does not exist.\n" <>
      "\n" <>
      "  ## Examples\n" <>
      "\n" <>
      "      iex> get_#{singular_name}!(123)\n" <>
      "      %#{module_name}{}\n" <>
      "\n" <>
      "      iex> get_#{singular_name}!(456)\n" <>
      "      ** (Ecto.NoResultsError)\n" <>
      "\n" <>
      "  \"\"\"\n" <>
      "  def get_#{singular_name}!(id), do: Repo.get!(#{module_name}, id)"
  end

  defp generate_create_function(singular_name, module_name) do
    "  @doc \"\"\"\n" <>
      "  Creates a #{singular_name}.\n" <>
      "\n" <>
      "  ## Examples\n" <>
      "\n" <>
      "      iex> create_#{singular_name}(%{field: value})\n" <>
      "      {:ok, %#{module_name}{}}\n" <>
      "\n" <>
      "      iex> create_#{singular_name}(%{field: bad_value})\n" <>
      "      {:error, %Ecto.Changeset{}}\n" <>
      "\n" <>
      "  \"\"\"\n" <>
      "  def create_#{singular_name}(attrs \\\\ %{}) do\n" <>
      "    %#{module_name}{}\n" <>
      "    |> #{module_name}.changeset(attrs)\n" <>
      "    |> Repo.insert()\n" <>
      "  end"
  end

  defp generate_update_function(singular_name, module_name) do
    "  @doc \"\"\"\n" <>
      "  Updates a #{singular_name}.\n" <>
      "\n" <>
      "  ## Examples\n" <>
      "\n" <>
      "      iex> update_#{singular_name}(#{singular_name}, %{field: new_value})\n" <>
      "      {:ok, %#{module_name}{}}\n" <>
      "\n" <>
      "      iex> update_#{singular_name}(#{singular_name}, %{field: bad_value})\n" <>
      "      {:error, %Ecto.Changeset{}}\n" <>
      "\n" <>
      "  \"\"\"\n" <>
      "  def update_#{singular_name}(%#{module_name}{} = #{singular_name}, attrs) do\n" <>
      "    #{singular_name}\n" <>
      "    |> #{module_name}.changeset(attrs)\n" <>
      "    |> Repo.update()\n" <>
      "  end"
  end

  defp generate_delete_function(singular_name, module_name) do
    "  @doc \"\"\"\n" <>
      "  Deletes a #{singular_name}.\n" <>
      "\n" <>
      "  ## Examples\n" <>
      "\n" <>
      "      iex> delete_#{singular_name}(#{singular_name})\n" <>
      "      {:ok, %#{module_name}{}}\n" <>
      "\n" <>
      "      iex> delete_#{singular_name}(#{singular_name})\n" <>
      "      {:error, %Ecto.Changeset{}}\n" <>
      "\n" <>
      "  \"\"\"\n" <>
      "  def delete_#{singular_name}(%#{module_name}{} = #{singular_name}) do\n" <>
      "    Repo.delete(#{singular_name})\n" <>
      "  end"
  end

  defp generate_change_function(singular_name, module_name) do
    "  @doc \"\"\"\n" <>
      "  Returns an `%Ecto.Changeset{}` for tracking #{singular_name} changes.\n" <>
      "\n" <>
      "  ## Examples\n" <>
      "\n" <>
      "      iex> change_#{singular_name}(#{singular_name})\n" <>
      "      %Ecto.Changeset{data: %#{module_name}{}}\n" <>
      "\n" <>
      "  \"\"\"\n" <>
      "  def change_#{singular_name}(%#{module_name}{} = #{singular_name}, attrs \\\\ %{}) do\n" <>
      "    #{module_name}.changeset(#{singular_name}, attrs)\n" <>
      "  end"
  end
end
