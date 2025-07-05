defmodule Introspex.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/cpursley/introspex"

  def project do
    [
      app: :introspex,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      package: package(),
      name: "Introspex",
      description: "Generate Ecto schemas from existing PostgreSQL database structures",
      source_url: @source_url,
      homepage_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto, "~> 3.10"},
      {:postgrex, "~> 0.17"},
      {:jason, "~> 1.4"},

      # Dev & Test
      {:ex_doc, "~> 0.31.1", only: :dev, runtime: false},
      {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.3", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      # Run tests and check coverage
      test: ["test", "coveralls"],
      # Run to check the quality of your code
      quality: [
        "format --check-formatted",
        "sobelow --config",
        "credo --only warning"
      ]
    ]
  end

  defp package do
    [
      name: :introspex,
      files: ~w(lib .formatter.exs mix.exs README* LICENSE* CHANGELOG*),
      maintainers: ["Chase Pursley"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
