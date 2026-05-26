defmodule GitHoox.Hooks.Credo do
  @moduledoc """
  Runs `mix credo` against staged Elixir files.

  ## Options

    * `:strict` — pass `--strict` to credo. Default `false`.

  ## Defaults

    * `stage_fixed: false`
    * `files: ~w(lib/**/*.ex test/**/*.exs)`
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Cmd
  alias GitHoox.Hooks.Helpers

  @opts_schema [
    strict: [
      type: :boolean,
      default: false,
      doc: "Pass `--strict` to credo."
    ]
  ]

  @impl true
  @spec default_opts() :: keyword()
  def default_opts do
    [stage_fixed: false, files: ~w(lib/**/*.ex test/**/*.exs)]
  end

  @impl true
  @spec opts_schema() :: keyword()
  def opts_schema, do: @opts_schema

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run([], _opts), do: :ok

  def run(files, opts) do
    strict = if Keyword.get(opts, :strict, false), do: ["--strict"], else: []
    args = ["credo"] ++ strict ++ ["--files-included" | files]

    case Cmd.run("mix", args, env: Helpers.env_opt(opts)) do
      {_, 0} -> :ok
      {out, code} -> {:error, {code, out}}
    end
  end
end
