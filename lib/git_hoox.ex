defmodule GitHoox do
  @moduledoc """
  Git hooks in pure Elixir. Configurable file globs, per-hook options,
  built-in support for `mix format`, Credo, ExUnit, and Dialyzer.

  ## Quickstart

      mix git_hoox.install

  Add hooks in `.git_hoox.exs`:

      %{
        hooks: [
          pre_commit: [
            {GitHoox.Hooks.Format, []},
            {GitHoox.Hooks.Credo, []}
          ]
        ]
      }

  See `GitHoox.Hook` for writing custom hooks.
  """

  @typedoc "Git lifecycle stage. See `git help hooks`."
  @type stage ::
          :pre_commit
          | :prepare_commit_msg
          | :commit_msg
          | :post_commit
          | :pre_rebase
          | :post_checkout
          | :post_merge
          | :pre_push

  @typedoc "Glob pattern matched against repo-relative paths."
  @type glob :: String.t()

  @typedoc "Repo-relative file path."
  @type path :: String.t()

  @typedoc "Hook entry in config: `{Module, keyword_opts}`."
  @type hook_entry :: {module(), keyword()}

  @typedoc "Loaded and validated config."
  @type config :: %{
          hooks: keyword(),
          parallel: boolean(),
          fail_fast: boolean(),
          skip_env: String.t()
        }

  @typedoc "Result of a single hook invocation."
  @type hook_result ::
          :ok
          | {:ok, modified :: [path()]}
          | :skip
          | {:error, term()}

  @doc """
  Execute all hooks configured for `stage`.

  `args` are the positional arguments the git shim received (e.g. the
  commit message file path for `commit_msg`). `stdin` is the raw input
  passed to the shim, only meaningful for `pre_push`.
  """
  @spec run(stage(), [String.t()], String.t() | nil) ::
          :ok | {:error, [{module(), term()}]}
  def run(stage, args \\ [], stdin \\ nil),
    do: GitHoox.Runner.run(stage, args, stdin)
end
