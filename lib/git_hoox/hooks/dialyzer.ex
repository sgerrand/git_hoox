defmodule GitHoox.Hooks.Dialyzer do
  @moduledoc """
  Runs `mix dialyzer --quiet`.

  **Slow** — PLT builds and whole-project analysis make this unsuitable
  for `pre_commit`. Configure on `pre_push`.

  ## Options

    * `:args` — extra CLI args appended after `--quiet`. Default `[]`.
      Example: `["--halt-exit-status"]`.

  Argument order: `mix dialyzer --quiet <user_args...>`.

  ## Defaults

    * `stage_fixed: false`
    * `files: ~w(lib/**/*.ex)`
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Cmd
  alias GitHoox.Hooks.Helpers

  @opts_schema [
    args: [
      type: {:list, :string},
      default: [],
      doc: "Extra CLI args appended after `--quiet`."
    ]
  ]

  @impl true
  @spec default_opts() :: keyword()
  def default_opts do
    [stage_fixed: false, files: ~w(lib/**/*.ex)]
  end

  @impl true
  @spec opts_schema() :: keyword()
  def opts_schema, do: @opts_schema

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run(_files, opts) do
    extra = Keyword.get(opts, :args, [])
    args = ["dialyzer", "--quiet" | extra]

    Cmd.run("mix", args, env: Helpers.env_opt(opts)) |> Helpers.to_result()
  end
end
