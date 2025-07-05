# Introspex

Generate Ecto schemas from existing PostgreSQL databases - including support for tables, views, materialized views, associations, and modern Ecto features.

## Installation

Add `introspex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:introspex, "~> 0.1.0"}]
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
    field :settings, :map  # JSONB column
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
    |> cast(attrs, [:email, :name, :age, :bio, :settings, :roles, :status, :company_id])
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
- **JSON**: json, jsonb → :map
- **Arrays**: integer[], text[] → {:array, :type}
- **Enums**: PostgreSQL enums → Ecto.Enum
- **PostGIS**: geometry, geography types
- **Network**: inet, cidr, macaddr
- **Special**: money, interval, tsvector

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