defmodule GitHoox.Hooks.Test do
  @moduledoc """
  Runs `mix test`.

  ## Options

    * `:scope` — `:all`, `:stale`, or `:related`. Default `:all`.

  ## Defaults

    * `stage_fixed: false`
    * `files: ~w(**/*.ex **/*.exs)`
    * `scope: :all`
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Cmd
  alias GitHoox.Hooks.Helpers

  @opts_schema [
    scope: [
      type: {:in, [:all, :stale, :related]},
      default: :all,
      doc: "Test selection strategy."
    ]
  ]

  @impl true
  @spec default_opts() :: keyword()
  def default_opts do
    [stage_fixed: false, files: ~w(**/*.ex **/*.exs), scope: :all]
  end

  @impl true
  @spec opts_schema() :: keyword()
  def opts_schema, do: @opts_schema

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run(files, opts) do
    args =
      case Keyword.get(opts, :scope, :all) do
        :stale -> ["test", "--stale"]
        :related -> ["test" | related_test_files(files)]
        _ -> ["test"]
      end

    case Cmd.run("mix", args, env: Helpers.env_opt(opts)) do
      {_, 0} -> :ok
      {out, code} -> {:error, {code, out}}
    end
  end

  defp related_test_files(files) do
    files
    |> Enum.map(&map_to_test/1)
    |> Enum.uniq()
    |> Enum.filter(&File.exists?/1)
  end

  defp map_to_test(path) do
    path
    |> String.replace(~r{^lib/}, "test/")
    |> String.replace(~r{\.ex$}, "_test.exs")
  end
end
