defmodule GitHoox.Hooks.Format do
  @moduledoc """
  Runs `mix format` against staged Elixir files.

  ## Options

    * `:check_only` — use `mix format --check-formatted`. Fails instead of mutating.
    * `:args` — extra CLI args appended after the task name (and the
      `--check-formatted` flag when `:check_only` is set). Default `[]`.

  Argument order: `mix format [--check-formatted] <user_args...> -- <files...>`.
  The `--` stops `mix format` parsing a `-`-prefixed filename as an option.

  ## Defaults

    * `stage_fixed: true`
    * `files: ~w(**/*.ex **/*.exs **/*.heex)` — matches root and nested paths.
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Hooks.Helpers

  @opts_schema [
    check_only: [
      type: :boolean,
      default: false,
      doc: "Use `mix format --check-formatted`. Fails instead of mutating."
    ],
    args: Helpers.args_schema("Extra CLI args appended after the task name and check flag.")
  ]

  @impl true
  @spec default_opts() :: keyword()
  def default_opts, do: [stage_fixed: true, files: ~w(**/*.ex **/*.exs **/*.heex)]

  @impl true
  @spec opts_schema() :: keyword()
  def opts_schema, do: @opts_schema

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run([], _opts), do: :ok

  def run(files, opts) do
    check? = Keyword.get(opts, :check_only, false)
    check_flag = if check?, do: ["--check-formatted"], else: []
    args = ["format"] ++ check_flag ++ Keyword.get(opts, :args, []) ++ ["--" | files]

    case Helpers.cmd("mix", args, opts) do
      # --check-formatted never writes, so there is nothing to re-stage and
      # no reason to pay for a `git diff` to find out.
      {_, 0} when check? -> :ok
      {_, 0} -> {:ok, GitHoox.Git.changed_in_worktree(files)}
      tuple -> Helpers.to_result(tuple)
    end
  end
end
