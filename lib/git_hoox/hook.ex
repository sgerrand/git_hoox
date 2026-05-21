defmodule GitHoox.Hook do
  @moduledoc """
  Behaviour for git_hoox hooks.

  Implement `run/2` to execute logic. Optionally implement `default_opts/0`
  to supply per-hook defaults (e.g. `stage_fixed: true` for formatters).

  ## Example

      defmodule MyApp.Hooks.Sobelow do
        @behaviour GitHoox.Hook

        @impl true
        def default_opts, do: [files: ~w(lib/**/*.ex)]

        @impl true
        def run([], _opts), do: :ok
        def run(files, _opts) do
          case System.cmd("mix", ["sobelow", "--exit" | files], stderr_to_stdout: true) do
            {_, 0} -> :ok
            {out, code} -> {:error, {code, out}}
          end
        end
      end

  """

  @typedoc "Files matched by hook's `:files` glob, after staging filter."
  @type files :: [GitHoox.path()]

  @typedoc "Hook options merged from `default_opts/0` and user config."
  @type opts :: keyword()

  @doc """
  Run hook against `files`.

  Return `:ok` for read-only success. Return `{:ok, modified}` listing files
  the hook mutated — runner re-stages them if `stage_fixed: true`.
  """
  @callback run(files(), opts()) :: GitHoox.hook_result()

  @doc """
  Per-hook default options. Merged with user config; user wins on conflict.
  """
  @callback default_opts() :: keyword()

  @optional_callbacks default_opts: 0
end
