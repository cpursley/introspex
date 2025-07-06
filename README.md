# Introspex

Generate Ecto schemas from existing PostgreSQL databases - including support for tables, views, materialized views, associations, and modern Ecto features.

**Perfect for migrating existing applications to Elixir** - Whether you're moving from Rails, Django, or any other framework with an existing PostgreSQL database or are using an external migration tool (i.e., not ecto migrations), Introspex helps you quickly generate Elixir/Ecto schemas that match your current database structure.

## Installation

Add `introspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:introspex, "~> 0.2.0", only: :dev}]
end
```

Then run:
```bash
mix deps.get
```

## Usage

### Basic Usage

Generate schemas for all tables and views in your database:

```bash
mix ecto.gen.schema --repo MyApp.Repo
```

### Generate for a Specific Table

```bash
mix ecto.gen.schema --repo MyApp.Repo --table users
```

### Exclude Views

By default, views and materialized views are included. To exclude them:

```bash
mix ecto.gen.schema --repo MyApp.Repo --exclude-views
```

### Use Binary IDs (UUIDs)

Generate schemas with UUID primary keys:

```bash
mix ecto.gen.schema --repo MyApp.Repo --binary-id
```

### Dry Run

Preview what will be generated without creating files:

```bash
mix ecto.gen.schema --repo MyApp.Repo --dry-run
```

### Phoenix Contexts

Generate schemas organized into Phoenix contexts. When using `--context-tables`, only the specified tables will be generated:

```bash
# Generate ONLY users and profiles tables in the Accounts context
mix ecto.gen.schema --repo MyApp.Repo --context Accounts --context-tables users,profiles

# Generate ONLY posts, comments, and tags tables in the Blog context
mix ecto.gen.schema --repo MyApp.Repo --context Blog --context-tables posts,comments,tags
```

When using contexts:
- A context module is generated at `lib/my_app/accounts.ex` with CRUD functions
- Schemas are organized into subdirectories:
  - `lib/my_app/accounts/user.ex` for `MyApp.Accounts.User`
  - `lib/my_app/accounts/profile.ex` for `MyApp.Accounts.Profile`
- Views and materialized views only get read operations (list and get) in the context module
- Duplicate function names are automatically prevented when tables have the same singular form (e.g., `user_account` and `user_accounts`)

### Custom Paths

Use the `--path` option to organize schemas in custom directory structures. Path segments are reflected in module names:

```bash
# Simple path - generates Services.Queries.Property module
mix ecto.gen.schema --repo Services.Repo --path queries --table property

# Path with underscores - generates MyApp.SomePath.User module  
mix ecto.gen.schema --repo MyApp.Repo --path some_path --table users

# Multiple path segments - generates MyApp.Admin.Reports.Metric module
mix ecto.gen.schema --repo MyApp.Repo --path admin/reports --table metrics
```

Combine with contexts for organized domain structure:

```bash
# Generates lib/my_app/queries/accounts.ex and lib/my_app/queries/accounts/user.ex
# Modules: MyApp.Queries.Accounts and MyApp.Queries.Accounts.User
mix ecto.gen.schema --repo MyApp.Repo --path queries --context Accounts --context-tables users,profiles
```

## Options

- `--repo` - The repository module (required)
- `--schema` - PostgreSQL schema name (default: "public")
- `--table` - Generate schema for a specific table only
- `--exclude-views` - Skip generating schemas for views and materialized views
- `--binary-id` - Use binary_id (UUID) for primary keys
- `--no-timestamps` - Do not generate timestamps() in schemas
- `--no-changesets` - Skip generating changeset functions
- `--no-associations` - Skip detecting and generating associations
- `--module-prefix` - Prefix for generated module names (default: app name)
- `--output-dir` - Output directory for schema files (default: lib/app_name)
- `--dry-run` - Preview what would be generated without writing files
- `--context` - Phoenix context name for organizing related schemas
- `--context-tables` - Comma-separated list of tables to include in the context (when specified, only these tables will be generated)
- `--path` - Custom path segment(s) to insert in the output directory (e.g., "queries" results in lib/app_name/queries/...)

## Example Output

For a `users` table with foreign keys and constraints:

```elixir
defmodule MyApp.User do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :name, :string
    field :age, :integer
    field :bio, :string
    field :activated_at, :utc_datetime
    field :roles, {:array, :string}
    field :status, Ecto.Enum, values: [:active, :inactive, :pending]
    
    belongs_to :company, MyApp.Company
    has_many :posts, MyApp.Post, foreign_key: :author_id
    many_to_many :teams, MyApp.Team, join_through: "users_teams"
    
    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :name, :age, :bio, :activated_at, :roles, :status, :company_id])
    |> validate_required([:email, :name])
    |> validate_format(:email, ~r/@/)
    |> unique_constraint(:email)
    |> foreign_key_constraint(:company_id)
  end
end
```

For a database view:

```elixir
defmodule MyApp.UserStats do
  @moduledoc "Schema for database view"
  use Ecto.Schema

  @schema_source_type :view

  schema "user_stats" do
    field :user_id, :integer
    field :posts_count, :integer
    field :comments_count, :integer
    field :last_activity, :utc_datetime
  end
end
```

## Supported Types

The generator supports all common PostgreSQL types including:

- **Basic Types**: integer, text, boolean, decimal, float
- **Date/Time**: date, time, timestamp, timestamptz
- **UUID**: uuid → :binary_id
- **JSON**: json, jsonb → (requires manual type specification, see below)
- **Arrays**: integer[], text[] → {:array, :type}
- **Enums**: PostgreSQL enums → Ecto.Enum
- **PostGIS**: geometry, geography types
- **Network**: inet, cidr, macaddr
- **Special**: money, interval, tsvector

## Mixed Foreign Key Types

When your database uses a mix of UUID and integer primary keys, Introspex automatically handles the type declarations. For example, if a table with UUID primary keys has a foreign key to a table with integer primary keys, the generator will add the appropriate `type: :id` option:

```elixir
@primary_key {:id, :binary_id, autogenerate: false}
@foreign_key_type :binary_id

schema "organizations" do
  # This foreign key is an integer, so type: :id is added automatically
  belongs_to :organization_role, MyApp.OrganizationRole, type: :id
  
  # These foreign keys are UUIDs, so they use the default @foreign_key_type
  belongs_to :user, MyApp.User
  belongs_to :account, MyApp.Account
end
```

## JSON/JSONB Fields

PostgreSQL's JSON and JSONB columns can store various data structures (objects, arrays, primitives), making it impossible to automatically determine the correct Ecto type. Therefore, these fields are commented out in generated schemas with examples to guide you:

```elixir
# JSONB field - requires manual type specification based on your data:
# field :contact_ids, :map                    # For JSON objects: {"key": "value"}
# field :contact_ids, {:array, :string}       # For string arrays: ["value1", "value2"]
# field :contact_ids, {:array, :integer}      # For integer arrays: [1, 2, 3]
# field :contact_ids, {:array, :map}          # For object arrays: [{"id": 1}, {"id": 2}]
```

You'll need to:
1. Uncomment the field
2. Choose the appropriate type based on your actual data structure
3. Update the changeset function to include the field

Common patterns:
- Use `:map` for JSON objects/documents
- Use `{:array, :string}` for arrays of UUIDs or strings
- Use `{:array, :integer}` for arrays of numeric IDs
- Use `{:array, :map}` for arrays of objects

## Requirements

- Elixir 1.14+
- Ecto 3.10+
- PostgreSQL 12+

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b feature/my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin feature/my-new-feature`)
5. Create new Pull Request

## Acknowledgments

Introspex was inspired by [ecto_generator](https://github.com/alexandrubagu/ecto_generator) created by [Alexandru Bogdan Bâgu](https://github.com/alexandrubagu). While Introspex is a complete rewrite with a different approach and feature set, the original project provided valuable inspiration for the concept of generating Ecto schemas from existing databases.

Maintained by [Chase Pursley](https://github.com/cpursley).

## License

MIT License - see LICENSE file for details