# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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