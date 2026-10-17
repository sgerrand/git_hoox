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
      {_, 0} -> scan_changed(files)
      tuple -> Helpers.to_result(tuple)
    end
  end

  # `mix format` has already exited 0 and rewritten the files by this
  # point, so a failure here is git's, not the formatter's. Tag it rather
  # than returning the bare `{code, out}` the formatter itself would
  # produce: reported untagged it reads as "Format failed", which blames
  # the wrong command and buries the part that matters — the files were
  # changed on disk and nothing was re-staged.
  defp scan_changed(files) do
    case GitHoox.Git.changed_in_worktree(files) do
      {:ok, _} = ok -> ok
      {:error, reason} -> {:error, {:restage_scan, reason}}
    end
  end
end
