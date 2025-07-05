defmodule Introspex do
  @moduledoc """
  Introspex generates Ecto schemas from existing PostgreSQL databases.

  This library introspects your PostgreSQL database and generates Ecto schema
  files with proper field types, associations, and changesets. It supports:

  - Tables, views, and materialized views
  - Automatic association detection (belongs_to, has_many, many_to_many)
  - Comprehensive type mapping (UUID, arrays, JSON, enums, PostGIS)
  - Changeset generation with validations
  - Modern Ecto best practices

  ## Usage

  Generate schemas for all tables and views:

      mix ecto.gen.schema --repo MyApp.Repo

  Generate for a specific table:

      mix ecto.gen.schema --repo MyApp.Repo --table users

  See `Mix.Tasks.Ecto.Gen.Schema` for all available options.
  """

  @version "0.1.0"

  @doc """
  Returns the current version of Introspex.
  """
  def version, do: @version
end
