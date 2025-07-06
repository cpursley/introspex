# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-01-06

### Added
- Phoenix context support with `--context` and `--context-tables` CLI options
  - Generate schemas organized into Phoenix contexts
  - Generates a context module file with CRUD functions (e.g., `lib/my_app/accounts.ex`)
  - Specify which tables belong to each context
  - Schemas are automatically placed in context subdirectories
  - When `--context-tables` is specified, only those tables will be generated
  - Views and materialized views only generate read operations (list and get)
  - Example: `--context Accounts --context-tables users,profiles`
- Custom path support with `--path` CLI option
  - Organize schemas in custom directory structures
  - Supports multiple path segments (e.g., `--path admin/reports`)
  - Works with contexts for flexible organization
  - Path segments are reflected in module names (e.g., `--path queries` → `MyApp.Queries.ModuleName`)
  - Example: `--path queries --context Accounts`

### Changed
- JSON/JSONB fields now generate as commented code with manual type instructions
  - Prevents runtime errors from incorrect type assumptions
  - Users must manually specify the correct type based on their data structure
  - Supports common patterns: objects, string arrays, integer arrays, etc.
  - Added comprehensive documentation and examples in generated code

### Fixed
- JSON/JSONB field handling to avoid runtime errors
- Improved type safety for complex PostgreSQL types
- Context modules now only generate read operations for views and materialized views
- Fixed duplicate alias compilation errors by using grouped alias syntax for multiple schemas
- Fixed duplicate function definitions in context modules when tables have the same singular form (e.g., `user_account` and `user_accounts`)
- Removed invalid `@schema_source_type` attribute for views/materialized views - added comment instead
- Added comprehensive documentation to all public functions
- Fixed unused alias warnings in context modules by only aliasing schemas that are actually used in generated functions
- Simplified association module references - now uses just the schema name instead of relative module paths
- Fixed association module references to use full module paths when generating schemas within contexts
- Fixed mixed foreign key type handling - automatically adds `type: :id` to belongs_to associations when foreign key is integer but schema uses binary_id

## [0.1.0] - 2025-01-05

### Initial Release

Introspex is a new Elixir library for generating Ecto schemas from existing PostgreSQL databases. While inspired by the original [ecto_generator](https://github.com/alexandrubagu/ecto_generator), Introspex is a complete rewrite with a focus on modern PostgreSQL and Ecto practices.

### Features
- Generate Ecto schemas from PostgreSQL tables, views, and materialized views
- Automatic association detection based on foreign keys
- Intelligent changeset generation with validations
- Comprehensive PostgreSQL type support including:
  - UUID primary keys with auto-detection
  - Arrays (both `[]` and `_` notation)
  - JSON/JSONB fields
  - Enums
  - PostGIS geometry types
  - Network types (inet, cidr, macaddr)
  - All standard SQL types
- Smart handling of database defaults - lets PostgreSQL manage them
- Proper timestamp detection - only uses `timestamps()` for Ecto-compatible columns
- Support for composite primary keys
- Dry-run mode for previewing generated schemas

### Fixed Issues (from initial development)
- Repo startup error handling for umbrella applications
- String interpolation in schema generation
- Proper UUID primary key detection and configuration
- PostgreSQL array type handling with underscore prefix
- Foreign key field deduplication with belongs_to associations
- Timestamp field detection for non-standard column names
- Database default value handling to prevent Ecto conflicts

### Requirements
- Elixir 1.14+
- Ecto 3.10+
- PostgreSQL 12+

### Acknowledgments
Inspired by [ecto_generator](https://github.com/alexandrubagu/ecto_generator) by Alexandru Bogdan Bâgu.