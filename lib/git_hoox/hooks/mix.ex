defmodule GitHoox.Hooks.Mix do
  @moduledoc """
  Runs an arbitrary `mix` task.

  Generic escape hatch for mix tasks that do not have a dedicated hook
  module (e.g. `mix docs`, `mix compile --warnings-as-errors`,
  `mix hex.outdated`, `mix deps.audit`).

  Prefer the dedicated hooks (`GitHoox.Hooks.Test`, `GitHoox.Hooks.Format`,
  `GitHoox.Hooks.Credo`, `GitHoox.Hooks.Dialyzer`) when they cover the task
  — they ship sensible defaults and first-class options (`:scope`,
  `:check_only`, `:strict`).

  ## Options

    * `:task` — mix task name. Required. Example: `"docs"`, `"compile"`,
      `"hex.outdated"`.
    * `:args` — extra CLI args appended after the task name. Default `[]`.
      Example: `["--warnings-as-errors"]`.
    * `:append_files` — append the matched file list as trailing arguments.
      Default `false`. Set to `true` for tasks that accept paths
      (e.g. a custom `mix lint <files>`); see "Empty file list" below.

  Argument order: `mix <task> <user_args...> [-- <files...>]`. The `--`
  is inserted only when `append_files: true`, and stops the task reading
  a filename that starts with `-` as an option. The invoked task must
  parse `--` as an options terminator — `OptionParser` does this, so any
  task built on `OptionParser.parse/2` (or `parse!/2`) is fine. A task
  that reads `System.argv/0` raw sees a literal `"--"` in its path list;
  use `GitHoox.Hooks.Shell` with `{files}` for those.

  ## Defaults

    * `stage_fixed: false`
    * `files: ["**/*"]`

  ## Empty file list

  When `append_files: true` and the runner passes an empty file list, the
  hook returns `:ok` without running mix. This avoids the trailing-space
  problem documented on `GitHoox.Hooks.Shell` — `mix sobelow --exit Low `
  is interpreted as "scan the entire project", which is the opposite of
  what the caller asked for. `append_files: false` runs the task
  regardless of file list.

  ## Examples

      # pre_commit
      {GitHoox.Hooks.Mix, task: "compile", args: ["--warnings-as-errors"]}
      {GitHoox.Hooks.Mix, task: "docs"}

      # pre_push
      {GitHoox.Hooks.Mix, task: "test", args: ["--warnings-as-errors", "--cover"]}
      {GitHoox.Hooks.Mix, task: "hex.outdated"}
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Hooks.Helpers

  @opts_schema [
    task: [
      type: :string,
      required: true,
      doc: "Mix task name (e.g. \"docs\", \"compile\")."
    ],
    args: Helpers.args_schema("Extra CLI args appended after the task name."),
    append_files: [
      type: :boolean,
      default: false,
      doc: "Append matched file list as trailing arguments."
    ]
  ]

  @impl true
  @spec default_opts() :: keyword()
  def default_opts, do: [stage_fixed: false, files: ["**/*"]]

  @impl true
  @spec opts_schema() :: keyword()
  def opts_schema, do: @opts_schema

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run(files, opts) do
    case Keyword.fetch(opts, :task) do
      {:ok, task} -> run_task(task, files, opts)
      :error -> {:error, "GitHoox.Hooks.Mix requires :task option"}
    end
  end

  defp run_task(task, files, opts) do
    args = Keyword.get(opts, :args, [])
    append? = Keyword.get(opts, :append_files, false)

    cond do
      append? and files == [] -> :ok
      append? -> Helpers.mix([task | args] ++ ["--" | files], opts)
      true -> Helpers.mix([task | args], opts)
    end
  end
end
