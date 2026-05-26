defmodule GitHoox.Hooks.Format do
  @moduledoc """
  Runs `mix format` against staged Elixir files.

  ## Options

    * `:check_only` — use `mix format --check-formatted`. Fails instead of mutating.

  ## Defaults

    * `stage_fixed: true`
    * `files: ~w(**/*.ex **/*.exs **/*.heex)` — matches root and nested paths.
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Cmd
  alias GitHoox.Hooks.Helpers

  @opts_schema [
    check_only: [
      type: :boolean,
      default: false,
      doc: "Use `mix format --check-formatted`. Fails instead of mutating."
    ]
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
    args =
      if Keyword.get(opts, :check_only, false) do
        ["format", "--check-formatted" | files]
      else
        ["format" | files]
      end

    case Cmd.run("mix", args, env: Helpers.env_opt(opts)) do
      {_, 0} ->
        {:ok, GitHoox.Git.changed_in_worktree(files)}

      {out, code} ->
        {:error, {code, out}}
    end
  end
end
