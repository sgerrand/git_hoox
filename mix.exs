defmodule GitHoox.MixProject do
  use Mix.Project

  @version "0.4.1"
  @source_url "https://github.com/sgerrand/git_hoox"

  def project do
    [
      app: :git_hoox,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      test_coverage: test_coverage(),
      name: "GitHoox",
      source_url: @source_url
    ]
  end

  def cli do
    [
      preferred_envs: [
        dialyzer: :dev,
        docs: :dev,
        "hex.publish": :dev,
        coveralls: :test,
        "coveralls.lcov": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:nimble_options, "~> 1.0"},
      {:telemetry, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test, runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Git hooks in pure Elixir. Configurable file globs, per-hook options, " <>
      "built-in support for mix format, Credo, ExUnit, and Dialyzer."
  end

  defp package do
    [
      name: "git_hoox",
      licenses: ["BSD-2-Clause"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      },
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "GitHoox",
      source_ref: "v#{@version}",
      extras: ["CHANGELOG.md", "LICENSE", "README.md"],
      groups_for_modules: [
        Core: [GitHoox, GitHoox.Hook, GitHoox.Runner, GitHoox.Config, GitHoox.Glob, GitHoox.Cmd],
        Git: [GitHoox.Git, GitHoox.Installer],
        Diagnostics: [GitHoox.Doctor, GitHoox.Bench],
        Observability: [GitHoox.Telemetry, GitHoox.Logger],
        "Built-in Hooks": [
          GitHoox.Hooks.Format,
          GitHoox.Hooks.Credo,
          GitHoox.Hooks.Test,
          GitHoox.Hooks.Dialyzer,
          GitHoox.Hooks.Shell
        ],
        "Mix Tasks": [
          Mix.Tasks.GitHoox.Install,
          Mix.Tasks.GitHoox.Uninstall,
          Mix.Tasks.GitHoox.Run,
          Mix.Tasks.GitHoox.Doctor,
          Mix.Tasks.GitHoox.List,
          Mix.Tasks.GitHoox.Bench
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [:error_handling, :unknown, :no_opaque, :extra_return]
    ]
  end

  defp test_coverage, do: [tool: ExCoveralls]
end
