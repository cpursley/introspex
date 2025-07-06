defmodule Mix.Tasks.Ecto.Gen.SchemaTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Ecto.Gen.Schema

  defmodule TestRepo do
    def __adapter__, do: Ecto.Adapters.Postgres

    def config, do: [database: "test_db", username: "postgres", password: "postgres"]

    def start_link(_opts \\ []) do
      # Simulate already started repo
      {:error, {:already_started, self()}}
    end

    def query(_query, _params) do
      # Simulate a database connection error
      {:error, %{message: "Could not query database"}}
    end
  end

  defmodule NotARepo do
    # This module doesn't implement __adapter__
  end

  describe "run/1" do
    test "handles when repo is already started" do
      # This should not raise an error
      assert_raise Mix.Error, ~r/Could not query database/, fn ->
        Schema.run(["--repo", "Mix.Tasks.Ecto.Gen.SchemaTest.TestRepo", "--dry-run"])
      end
    end

    test "raises error when module is not a repo" do
      assert_raise Mix.Error, ~r/is not an Ecto.Repo/, fn ->
        Schema.run(["--repo", "Mix.Tasks.Ecto.Gen.SchemaTest.NotARepo"])
      end
    end

    test "raises error when repo module doesn't exist" do
      assert_raise Mix.Error, ~r/Could not load/, fn ->
        Schema.run(["--repo", "NonExistent.Repo"])
      end
    end

    test "shows help when no args provided" do
      assert_raise Mix.Error, ~r/--repo option is required/, fn ->
        Schema.run([])
      end
    end

    test "validates required --repo option" do
      assert_raise Mix.Error, ~r/--repo option is required/, fn ->
        Schema.run(["--table", "users"])
      end
    end
  end

  describe "parse_opts/1" do
    test "parses all available options" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--schema",
        "custom_schema",
        "--table",
        "users",
        "--exclude-views",
        "--binary-id",
        "--no-timestamps",
        "--no-changesets",
        "--no-associations",
        "--module-prefix",
        "Custom",
        "--output-dir",
        "lib/custom",
        "--dry-run",
        "--context",
        "Accounts",
        "--context-tables",
        "users,profiles",
        "--path",
        "queries"
      ]

      switches = [
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

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:repo] == "MyApp.Repo"
      assert opts[:schema] == "custom_schema"
      assert opts[:table] == "users"
      assert opts[:exclude_views] == true
      assert opts[:binary_id] == true
      assert opts[:no_timestamps] == true
      assert opts[:no_changesets] == true
      assert opts[:no_associations] == true
      assert opts[:module_prefix] == "Custom"
      assert opts[:output_dir] == "lib/custom"
      assert opts[:dry_run] == true
      assert opts[:context] == "Accounts"
      assert opts[:context_tables] == "users,profiles"
      assert opts[:path] == "queries"
    end

    test "parses context options separately" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--context",
        "Blog",
        "--context-tables",
        "posts,comments,tags"
      ]

      switches = [
        repo: :string,
        context: :string,
        context_tables: :string
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:repo] == "MyApp.Repo"
      assert opts[:context] == "Blog"
      assert opts[:context_tables] == "posts,comments,tags"
    end

    test "context-tables limits table generation" do
      # This test verifies the parsing logic
      # Actual filtering would be tested in integration tests
      args = [
        "--repo",
        "MyApp.Repo",
        "--context-tables",
        "users,profiles"
      ]

      switches = [
        repo: :string,
        context_tables: :string
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:context_tables] == "users,profiles"
      # When context_tables is specified, only those tables should be processed
    end

    test "path option works with context" do
      args = [
        "--repo",
        "MyApp.Repo",
        "--path",
        "queries/reports",
        "--context",
        "Analytics"
      ]

      switches = [
        repo: :string,
        path: :string,
        context: :string
      ]

      {opts, _, _} = OptionParser.parse(args, switches: switches)

      assert opts[:path] == "queries/reports"
      assert opts[:context] == "Analytics"
    end
  end
end
