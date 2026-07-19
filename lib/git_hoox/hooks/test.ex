defmodule GitHoox.Hooks.Test do
  @moduledoc """
  Runs `mix test`.

  ## Options

    * `:scope` — `:all`, `:stale`, or `:related`. Default `:all`.
    * `:args` — extra CLI args appended after the task name and any
      scope-derived flag. Default `[]`. Example:
      `["--warnings-as-errors"]`.

  Argument order: `mix test [--stale] <user_args...> [-- <related_test_files>]`.
  The `--` before related paths stops `mix test` parsing a `-`-prefixed path
  as an option.

  ## Defaults

    * `stage_fixed: false`
    * `files: ~w(**/*.ex **/*.exs)`
    * `scope: :all`

  ## `:related` with no resolvable tests

  When `scope: :related` is selected and `related_test_files/1` produces
  an empty list (no `lib/foo.ex → test/foo_test.exs` mappings exist on
  disk), the hook returns `:ok` without invoking `mix test`. Falling
  through to a bare `mix test` would silently run the entire suite,
  which is the opposite of what the caller asked for.
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Cmd
  alias GitHoox.Hooks.Helpers

  @opts_schema [
    scope: [
      type: {:in, [:all, :stale, :related]},
      default: :all,
      doc: "Test selection strategy."
    ],
    args: [
      type: {:list, :string},
      default: [],
      doc: "Extra CLI args appended after the task name and scope flag."
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
    extra = Keyword.get(opts, :args, [])

    case Keyword.get(opts, :scope, :all) do
      :stale -> exec(["test", "--stale" | extra], opts)
      :related -> run_related(files, extra, opts)
      _ -> exec(["test" | extra], opts)
    end
  end

  defp run_related(files, extra, opts) do
    case related_test_files(files) do
      [] -> :ok
      related -> exec(["test" | extra] ++ ["--" | related], opts)
    end
  end

  defp exec(args, opts) do
    Cmd.run("mix", args, env: Helpers.env_opt(opts)) |> Helpers.to_result()
  end

  defp related_test_files(files) do
    files
    |> Enum.map(&map_to_test/1)
    |> Enum.uniq()
    |> Enum.filter(&File.exists?/1)
  end

  @lib_prefix ~r{^lib/}
  @ex_suffix ~r{\.ex$}

  defp map_to_test(path) do
    path
    |> String.replace(@lib_prefix, "test/")
    |> String.replace(@ex_suffix, "_test.exs")
  end
end
