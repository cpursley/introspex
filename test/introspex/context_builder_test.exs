defmodule Introspex.ContextBuilderTest do
  use ExUnit.Case

  alias Introspex.ContextBuilder

  describe "build_context/3" do
    test "generates context module without path" do
      schemas = [
        %{
          module_name: "User",
          singular_name: "user",
          plural_name: "users"
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo"
      ]

      result = ContextBuilder.build_context("Accounts", schemas, opts)

      assert result =~ "defmodule MyApp.Accounts do"
      assert result =~ "alias MyApp.Accounts.User"
      assert result =~ "def list_users do"
      assert result =~ "def get_user!(id)"
      assert result =~ "def create_user(attrs \\\\ %{})"
      assert result =~ "def update_user(%User{} = user, attrs)"
      assert result =~ "def delete_user(%User{} = user)"
      assert result =~ "def change_user(%User{} = user, attrs \\\\ %{})"
    end

    test "generates context module with single path segment" do
      schemas = [
        %{
          module_name: "Account",
          singular_name: "account",
          plural_name: "accounts"
        }
      ]

      opts = [
        app_name: "Services",
        repo_module: "Services.Repo",
        path: "queries"
      ]

      result = ContextBuilder.build_context("UserAccounts", schemas, opts)

      assert result =~ "defmodule Services.Queries.UserAccounts do"
      assert result =~ "alias Services.Queries.UserAccounts.Account"
    end

    test "generates context module with multiple path segments" do
      schemas = [
        %{
          module_name: "Report",
          singular_name: "report",
          plural_name: "reports"
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo",
        path: "admin/analytics"
      ]

      result = ContextBuilder.build_context("Reporting", schemas, opts)

      assert result =~ "defmodule MyApp.Admin.Analytics.Reporting do"
      assert result =~ "alias MyApp.Admin.Analytics.Reporting.Report"
    end

    test "handles underscored path segments correctly" do
      schemas = [
        %{
          module_name: "UserProfile",
          singular_name: "user_profile",
          plural_name: "user_profiles"
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo",
        path: "some_path/another_path"
      ]

      result = ContextBuilder.build_context("Accounts", schemas, opts)

      assert result =~ "defmodule MyApp.SomePath.AnotherPath.Accounts do"
      assert result =~ "alias MyApp.SomePath.AnotherPath.Accounts.UserProfile"
    end

    test "generates only read operations for views" do
      schemas = [
        %{
          module_name: "UserReport",
          singular_name: "user_report",
          plural_name: "user_reports",
          table_type: :view
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo"
      ]

      result = ContextBuilder.build_context("Analytics", schemas, opts)

      # Should have read operations
      assert result =~ "def list_user_reports do"
      assert result =~ "def get_user_report!(id)"

      # Should NOT have write operations
      refute result =~ "def create_user_report"
      refute result =~ "def update_user_report"
      refute result =~ "def delete_user_report"
      refute result =~ "def change_user_report"
    end

    test "generates only read operations for materialized views" do
      schemas = [
        %{
          module_name: "SalesSnapshot",
          singular_name: "sales_snapshot",
          plural_name: "sales_snapshots",
          table_type: :materialized_view
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo"
      ]

      result = ContextBuilder.build_context("Reports", schemas, opts)

      # Should have read operations
      assert result =~ "def list_sales_snapshots do"
      assert result =~ "def get_sales_snapshot!(id)"

      # Should NOT have write operations
      refute result =~ "def create_sales_snapshot"
      refute result =~ "def update_sales_snapshot"
      refute result =~ "def delete_sales_snapshot"
      refute result =~ "def change_sales_snapshot"
    end

    test "generates full CRUD for tables alongside read-only for views" do
      schemas = [
        %{
          module_name: "User",
          singular_name: "user",
          plural_name: "users",
          table_type: :table
        },
        %{
          module_name: "UserActivity",
          singular_name: "user_activity",
          plural_name: "user_activities",
          table_type: :view
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo"
      ]

      result = ContextBuilder.build_context("Accounts", schemas, opts)

      # Table should have full CRUD
      assert result =~ "def list_users do"
      assert result =~ "def get_user!(id)"
      assert result =~ "def create_user(attrs \\\\ %{})"
      assert result =~ "def update_user(%User{} = user, attrs)"
      assert result =~ "def delete_user(%User{} = user)"
      assert result =~ "def change_user(%User{} = user, attrs \\\\ %{})"

      # View should have only read operations
      assert result =~ "def list_user_activities do"
      assert result =~ "def get_user_activity!(id)"
      refute result =~ "def create_user_activity"
      refute result =~ "def update_user_activity"
      refute result =~ "def delete_user_activity"
      refute result =~ "def change_user_activity"
    end

    test "generates grouped aliases for multiple schemas" do
      schemas = [
        %{
          module_name: "Organization",
          singular_name: "organization",
          plural_name: "organizations",
          table_type: :table
        },
        %{
          module_name: "UserAccount",
          singular_name: "user_account",
          plural_name: "user_accounts",
          table_type: :table
        },
        %{
          module_name: "UserProfile",
          singular_name: "user_profile",
          plural_name: "user_profiles",
          table_type: :table
        }
      ]

      opts = [
        app_name: "Services",
        repo_module: "Services.Repo",
        path: "database"
      ]

      result = ContextBuilder.build_context("Accounts", schemas, opts)

      # Should have grouped alias format
      assert result =~ "alias Services.Database.Accounts"
      assert result =~ "alias Accounts.{"
      assert result =~ "Organization,"
      assert result =~ "UserAccount,"
      assert result =~ "UserProfile"
    end

    test "generates single alias for one schema" do
      schemas = [
        %{
          module_name: "User",
          singular_name: "user",
          plural_name: "users",
          table_type: :table
        }
      ]

      opts = [
        app_name: "MyApp",
        repo_module: "MyApp.Repo"
      ]

      result = ContextBuilder.build_context("Accounts", schemas, opts)

      # Should have single alias format
      assert result =~ "alias MyApp.Accounts.User"
      refute result =~ "alias Accounts.{"
    end

    test "handles duplicate function names from similar table names" do
      schemas = [
        %{
          module_name: "UserAccount",
          singular_name: "user_account",
          plural_name: "user_accounts",
          table_type: :table
        },
        %{
          module_name: "UserAccounts",
          # Same singular form!
          singular_name: "user_account",
          plural_name: "user_accounts",
          table_type: :table
        }
      ]

      opts = [
        app_name: "Services",
        repo_module: "Services.Repo"
      ]

      result = ContextBuilder.build_context("Accounts", schemas, opts)

      # Should only have one set of functions for user_account
      # Count occurrences of function definitions
      list_count = length(String.split(result, "def list_user_accounts")) - 1
      get_count = length(String.split(result, "def get_user_account!")) - 1
      create_count = length(String.split(result, "def create_user_account")) - 1
      update_count = length(String.split(result, "def update_user_account")) - 1
      delete_count = length(String.split(result, "def delete_user_account")) - 1
      change_count = length(String.split(result, "def change_user_account")) - 1

      assert list_count == 1, "Expected 1 list function, got #{list_count}"
      assert get_count == 1, "Expected 1 get function, got #{get_count}"
      assert create_count == 1, "Expected 1 create function, got #{create_count}"
      assert update_count == 1, "Expected 1 update function, got #{update_count}"
      assert delete_count == 1, "Expected 1 delete function, got #{delete_count}"
      assert change_count == 1, "Expected 1 change function, got #{change_count}"
    end
  end
end
