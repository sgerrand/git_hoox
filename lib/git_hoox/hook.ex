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
  the hook mutated — runner re-stages them if `stage_fixed: true`. Return
  `{:error, reason}` to fail. The runner accepts no other shapes; anything
  else is a contract violation. The runner emits its own
  `[:git_hoox, :hook, :skip]` telemetry event when a hook's `:files` glob
  filters every candidate out — hook authors should not return `:skip`
  themselves.
  """
  @callback run(files(), opts()) :: GitHoox.hook_result()

  @doc """
  Per-hook default options. Merged with user config; user wins on conflict.
  """
  @callback default_opts() :: keyword()

  @doc """
  Hook-specific [NimbleOptions](https://hexdocs.pm/nimble_options) schema.

  Used by `GitHoox.Config` to validate any opts the user passes that are
  not part of the global schema (`:files`, `:stage_fixed`, `:timeout`,
  `:env`). Hooks that do not implement this callback accept arbitrary
  extra opts without validation.
  """
  @callback opts_schema() :: keyword()

  @optional_callbacks default_opts: 0, opts_schema: 0

  @doc """
  Merge a hook module's `default_opts/0` with user-supplied opts.

  User opts win on conflict. Modules without `default_opts/0` contribute
  an empty list.
  """
  @spec merge_defaults(module(), opts()) :: opts()
  def merge_defaults(mod, user_opts) when is_atom(mod) and is_list(user_opts) do
    defaults =
      if function_exported?(mod, :default_opts, 0),
        do: mod.default_opts(),
        else: []

    Keyword.merge(defaults, user_opts)
  end
end
