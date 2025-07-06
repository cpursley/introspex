defmodule Introspex.SchemaBuilderTest do
  use ExUnit.Case, async: true

  alias Introspex.SchemaBuilder

  describe "build_schema/3" do
    test "handles database function defaults" do
      table_info = %{
        table: %{name: "accounts", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "created_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "verification_token",
            data_type: "varchar",
            not_null: false,
            default: "uuid_generate_v4()",
            comment: nil,
            position: 4,
            enum_values: nil
          },
          %{
            name: "active",
            data_type: "boolean",
            not_null: true,
            default: "true",
            comment: nil,
            position: 5,
            enum_values: nil
          },
          %{
            name: "priority",
            data_type: "integer",
            not_null: true,
            default: "1",
            comment: nil,
            position: 6,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Account")

      # No defaults should be included - let PostgreSQL handle them all
      refute result =~ ~s|default: "gen_random_uuid()"|
      refute result =~ ~s|default: "now()"|
      refute result =~ ~s|default: "uuid_generate_v4()"|
      refute result =~ "default: true"
      refute result =~ "default: 1"

      # All fields should be simple without defaults
      assert result =~ "field :created_at, :naive_datetime"
      assert result =~ "field :verification_token, :string"
      assert result =~ "field :active, :boolean"
      assert result =~ "field :priority, :integer"
    end

    test "generates schema with UUID primary key when detected" do
      table_info = %{
        table: %{name: "users", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "email",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "active",
            data_type: "boolean",
            not_null: true,
            default: "true",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "inserted_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 4,
            enum_values: nil
          },
          %{
            name: "updated_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 5,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [%{constraint_name: "users_email_key", columns: ["email"]}],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.User")

      assert result =~ "@primary_key {:id, :binary_id, autogenerate: false}"
      assert result =~ "@foreign_key_type :binary_id"
      assert result =~ "field :email, :string"
      assert result =~ "field :active, :boolean"
      assert result =~ "timestamps()"
      assert result =~ "unique_constraint(:email)"
    end

    test "generates schema with integer primary key" do
      table_info = %{
        table: %{name: "posts", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "integer",
            not_null: true,
            default: "nextval",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "title",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Post")

      refute result =~ "@primary_key"
      assert result =~ "schema \"posts\" do"
      assert result =~ "field :title, :string"
    end

    test "handles non-standard primary key name with UUID" do
      table_info = %{
        table: %{name: "accounts", type: :table, comment: nil},
        columns: [
          %{
            name: "account_id",
            data_type: "uuid",
            not_null: true,
            default: nil,
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: ["account_id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Account")

      assert result =~ "@primary_key {:account_id, :binary_id, autogenerate: true}"
      assert result =~ "field :name, :string"
    end

    test "handles composite primary keys" do
      table_info = %{
        table: %{name: "user_roles", type: :table, comment: nil},
        columns: [
          %{
            name: "user_id",
            data_type: "uuid",
            not_null: true,
            default: nil,
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "role_id",
            data_type: "uuid",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: ["user_id", "role_id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.UserRole")

      assert result =~ "@primary_key false"
      assert result =~ "field :user_id, :binary_id"
      assert result =~ "field :role_id, :binary_id"
    end

    test "excludes database defaults from schema" do
      table_info = %{
        table: %{name: "settings", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "integer",
            not_null: true,
            default: "nextval",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "enabled",
            data_type: "boolean",
            not_null: true,
            default: "true",
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "disabled",
            data_type: "boolean",
            not_null: true,
            default: "false",
            comment: nil,
            position: 3,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Setting")

      assert result =~ "field :enabled, :boolean"
      assert result =~ "field :disabled, :boolean"
    end

    test "excludes numeric defaults from schema" do
      table_info = %{
        table: %{name: "products", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "integer",
            not_null: true,
            default: "nextval",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "quantity",
            data_type: "integer",
            not_null: true,
            default: "10",
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "price",
            data_type: "numeric",
            not_null: true,
            default: "99.99",
            comment: nil,
            position: 3,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Product")

      assert result =~ "field :quantity, :integer"
      assert result =~ "field :price, :decimal"
    end

    test "handles views without timestamps or changesets" do
      table_info = %{
        table: %{name: "user_stats", type: :view, comment: nil},
        columns: [
          %{
            name: "user_id",
            data_type: "uuid",
            not_null: true,
            default: nil,
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "posts_count",
            data_type: "integer",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: [],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :view
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.UserStats")

      assert result =~
               "# This is a view - queries will work but inserts/updates/deletes are not supported"

      assert result =~ "@primary_key false"
      assert result =~ "field :user_id, :binary_id"
      assert result =~ "field :posts_count, :integer"
      refute result =~ "timestamps()"
      refute result =~ "def changeset"
    end

    test "handles materialized views" do
      table_info = %{
        table: %{name: "cache_stats", type: :materialized_view, comment: nil},
        columns: [
          %{
            name: "stat_key",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "stat_value",
            data_type: "integer",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: [],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :materialized_view
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.CacheStats")

      assert result =~
               "# This is a materialized_view - queries will work but inserts/updates/deletes are not supported"

      assert result =~ "@primary_key false"
    end

    test "handles binary_id option override" do
      table_info = %{
        table: %{name: "items", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "integer",
            not_null: true,
            default: "nextval",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Item", binary_id: true)

      assert result =~ "@primary_key {:id, :binary_id, autogenerate: true}"
      assert result =~ "@foreign_key_type :binary_id"
    end

    test "handles relationships" do
      table_info = %{
        table: %{name: "posts", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "user_id",
            data_type: "uuid",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "title",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 3,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{
          belongs_to: [
            %{
              field: :user,
              table: "users",
              module: "User",
              foreign_key: :user_id,
              references: :id,
              type: :binary_id
            }
          ],
          has_many: [],
          many_to_many: []
        },
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Post")

      assert result =~ "belongs_to :user, User, type: :binary_id"
      assert result =~ "field :title, :string"
      # belongs_to fields are excluded
      refute result =~ "field :user_id"
    end

    test "handles enums" do
      table_info = %{
        table: %{name: "orders", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "status",
            data_type: "USER-DEFINED",
            not_null: true,
            default: "pending",
            comment: nil,
            position: 2,
            enum_values: ["pending", "processing", "completed", "cancelled"]
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Order")

      assert result =~
               "field :status, Ecto.Enum, values: [:pending, :processing, :completed, :cancelled]"
    end

    test "handles arrays" do
      table_info = %{
        table: %{name: "tags", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "labels",
            data_type: "_text",
            not_null: true,
            default: "{}",
            comment: nil,
            position: 2,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Tag")

      assert result =~ "field :labels, {:array, :string}"
    end

    test "excludes timestamp fields when using timestamps()" do
      table_info = %{
        table: %{name: "articles", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "title",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "inserted_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "updated_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 4,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Article")

      assert result =~ "timestamps()"
      refute result =~ "field :inserted_at"
      refute result =~ "field :updated_at"
    end

    test "handles non-standard timestamp columns (created_at instead of inserted_at)" do
      table_info = %{
        table: %{name: "posts", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "title",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "created_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "updated_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 4,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Post")

      # Should not use timestamps() because created_at is not inserted_at
      refute result =~ "timestamps()"
      assert result =~ "field :created_at, :naive_datetime"
      assert result =~ "field :updated_at, :naive_datetime"
    end

    test "handles timestamp columns with incompatible types" do
      table_info = %{
        table: %{name: "events", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "inserted_at",
            # Wrong type - should be timestamp
            data_type: "date",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "updated_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 4,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Event")

      # Should not use timestamps() because inserted_at has wrong type
      refute result =~ "timestamps()"
      assert result =~ "field :inserted_at, :date"
      assert result =~ "field :updated_at, :naive_datetime"
    end

    test "handles only one timestamp column present" do
      table_info = %{
        table: %{name: "logs", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "message",
            data_type: "text",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "inserted_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 3,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Log")

      # Should not use timestamps() because only inserted_at is present
      refute result =~ "timestamps()"
      assert result =~ "field :inserted_at, :naive_datetime"
    end

    test "includes timestamp fields when skip_timestamps option is true" do
      table_info = %{
        table: %{name: "articles", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "title",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "inserted_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "updated_at",
            data_type: "timestamp",
            not_null: true,
            default: "now()",
            comment: nil,
            position: 4,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Article", skip_timestamps: true)

      refute result =~ "timestamps()"
      assert result =~ "field :inserted_at, :naive_datetime"
      assert result =~ "field :updated_at, :naive_datetime"
    end

    test "handles PostGIS Geography fields correctly" do
      table_info = %{
        table: %{name: "locations", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "location_geography",
            data_type: "geography",
            not_null: false,
            default: nil,
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "location_geometry",
            data_type: "geometry",
            not_null: false,
            default: nil,
            comment: nil,
            position: 4,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Location")

      # Should use Geo.PostGIS.Geometry for both geometry and geography types
      assert result =~ "field :location_geography, Geo.PostGIS.Geometry"
      assert result =~ "field :location_geometry, Geo.PostGIS.Geometry"
      # Should not have the alias anymore
      refute result =~ "alias Geo.PostGIS"
    end

    test "handles JSONB fields with array defaults" do
      table_info = %{
        table: %{name: "clients", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "linked_client_ids",
            data_type: "jsonb",
            not_null: true,
            default: "jsonb_build_array()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          %{
            name: "tags",
            data_type: "jsonb",
            not_null: false,
            default: "'[]'::jsonb",
            comment: nil,
            position: 4,
            enum_values: nil
          },
          %{
            name: "metadata",
            data_type: "jsonb",
            not_null: false,
            default: "'{}'::jsonb",
            comment: nil,
            position: 5,
            enum_values: nil
          },
          %{
            name: "settings",
            data_type: "jsonb",
            not_null: false,
            default: nil,
            comment: nil,
            position: 6,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Client")

      # All JSONB fields should be commented out with manual instructions
      assert result =~ "# JSONB field - requires manual type specification based on your data:"
      assert result =~ "# field :linked_client_ids"
      assert result =~ "# field :tags"
      assert result =~ "# field :metadata"
      assert result =~ "# field :settings"
    end

    test "handles schemas with many fields without truncation" do
      # Generate 100 fields to test truncation handling
      many_columns =
        Enum.map(1..100, fn i ->
          %{
            name: "field_#{i}",
            data_type: "varchar",
            not_null: false,
            default: nil,
            comment: nil,
            position: i + 1,
            enum_values: nil
          }
        end)

      columns =
        [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          }
        ] ++ many_columns

      table_info = %{
        table: %{name: "large_table", type: :table, comment: nil},
        columns: columns,
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.LargeTable")

      # The cast call should include all fields without truncation (no "...")
      refute result =~ "..."

      # Check that all fields are present
      assert result =~ "field :field_1, :string"
      assert result =~ "field :field_50, :string"
      assert result =~ "field :field_100, :string"

      # Check that the cast includes all fields
      assert result =~ ":field_1"
      assert result =~ ":field_100"
    end

    test "handles various JSONB array scenarios correctly" do
      table_info = %{
        table: %{name: "todos", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          # Array of tag IDs
          %{
            name: "tag_ids",
            data_type: "jsonb",
            not_null: false,
            default: "jsonb_build_array()",
            comment: nil,
            position: 2,
            enum_values: nil
          },
          # Array of category names
          %{
            name: "category_names",
            data_type: "jsonb",
            not_null: false,
            default: "jsonb_build_array()",
            comment: nil,
            position: 3,
            enum_values: nil
          },
          # Array of attachment objects
          %{
            name: "attachments",
            data_type: "jsonb",
            not_null: false,
            default: "jsonb_build_array()",
            comment: nil,
            position: 4,
            enum_values: nil
          },
          # Non-array JSONB (object for metadata)
          %{
            name: "metadata",
            data_type: "jsonb",
            not_null: false,
            default: nil,
            comment: nil,
            position: 5,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{belongs_to: [], has_many: [], many_to_many: []},
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Todo")

      # All JSONB fields should be commented out with manual instructions
      assert result =~ "# JSONB field - requires manual type specification based on your data:"
      assert result =~ "# field :tag_ids"
      assert result =~ "# field :category_names"
      assert result =~ "# field :attachments"
      assert result =~ "# field :metadata"
    end

    test "adds type: :id to belongs_to when foreign key is integer but schema uses binary_id" do
      table_info = %{
        table: %{name: "organizations", type: :table, comment: nil},
        columns: [
          %{
            name: "id",
            data_type: "uuid",
            not_null: true,
            default: "gen_random_uuid()",
            comment: nil,
            position: 1,
            enum_values: nil
          },
          %{
            name: "name",
            data_type: "varchar",
            not_null: true,
            default: nil,
            comment: nil,
            position: 2,
            enum_values: nil
          },
          %{
            name: "role_id",
            data_type: "integer",
            not_null: true,
            default: nil,
            comment: nil,
            position: 3,
            enum_values: nil
          }
        ],
        primary_keys: ["id"],
        relationships: %{
          belongs_to: [
            %{
              field: :role,
              table: "roles",
              foreign_key: :role_id,
              references: :id,
              on_update: :cascade,
              on_delete: :cascade
            }
          ],
          has_many: [],
          many_to_many: []
        },
        unique_constraints: [],
        check_constraints: [],
        table_type: :table
      }

      result = SchemaBuilder.build_schema(table_info, "MyApp.Organization", binary_id: true)

      # Should have binary_id as primary key type
      assert result =~ "@primary_key {:id, :binary_id, autogenerate: false}"
      assert result =~ "@foreign_key_type :binary_id"

      # Should add type: :id to the belongs_to association
      assert result =~ "belongs_to :role, Roles, type: :id"
    end
  end
end
