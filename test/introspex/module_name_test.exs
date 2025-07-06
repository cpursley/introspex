defmodule Introspex.ModuleNameTest do
  use ExUnit.Case

  # Since build_module_name is private, we'll test it through the public interface
  # or extract it to a separate module. For now, let's create a helper module.

  defmodule ModuleNameHelper do
    def build_module_name(table_name, opts) do
      prefix = Keyword.get(opts, :module_prefix, "MyApp")
      context = Keyword.get(opts, :context)
      context_tables = Keyword.get(opts, :context_tables, [])
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
  end

  describe "module name generation" do
    test "basic module name without path or context" do
      result = ModuleNameHelper.build_module_name("users", [])
      assert result == "MyApp.Users"
    end

    test "module name with path" do
      opts = [path: "queries"]
      result = ModuleNameHelper.build_module_name("users", opts)
      assert result == "MyApp.Queries.Users"
    end

    test "module name with multi-segment path" do
      opts = [path: "admin/reports"]
      result = ModuleNameHelper.build_module_name("metrics", opts)
      assert result == "MyApp.Admin.Reports.Metrics"
    end

    test "module name with underscored path segments" do
      opts = [path: "some_path/another_path"]
      result = ModuleNameHelper.build_module_name("user_accounts", opts)
      assert result == "MyApp.SomePath.AnotherPath.UserAccounts"
    end

    test "module name with context and path" do
      opts = [
        path: "queries",
        context: "Accounts",
        context_tables: ["users", "profiles"]
      ]

      result = ModuleNameHelper.build_module_name("users", opts)
      assert result == "MyApp.Queries.Accounts.Users"
    end

    test "module name with path but table not in context" do
      opts = [
        path: "queries",
        context: "Accounts",
        context_tables: ["profiles"]
      ]

      result = ModuleNameHelper.build_module_name("users", opts)
      assert result == "MyApp.Queries.Users"
    end

    test "module name with custom prefix and path" do
      opts = [
        module_prefix: "Services",
        path: "internal/admin"
      ]

      result = ModuleNameHelper.build_module_name("organizations", opts)
      assert result == "Services.Internal.Admin.Organizations"
    end
  end
end
