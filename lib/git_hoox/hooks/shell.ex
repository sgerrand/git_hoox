defmodule GitHoox.Hooks.Shell do
  @moduledoc """
  Escape hatch for arbitrary shell commands.

  ## Options

    * `:run` — command string. Required. Supports template variables:
      * `{files}` — space-separated paths passed to the hook (stage-specific
        source, e.g. staged files for `pre_commit`, the commit-message path
        for `commit_msg`).
      * `{staged_files}` — `git diff --cached --name-only --diff-filter=ACMR`,
        looked up at call time regardless of stage.
      * `{all_files}` — `git ls-files`, looked up at call time.
      * `{push_files}` — paths parsed from `pre_push` stdin. Only valid in
        the `pre_push` stage; the hook returns an error if used elsewhere.
    * `:shell` — shell executable. Default `"sh"`.

  ## Defaults

    * `stage_fixed: false`

  ## Behaviour with no matching files

  When the template references `{files}` or `{push_files}` and the hook is
  invoked with an empty file list, the hook returns `:ok` without running
  the shell command. This avoids "empty argument" substitutions like
  `mix sobelow --exit Low ` — a trailing space which `mix sobelow`
  interprets as "scan the entire project", typically the opposite of what
  the caller wanted. The same skip applies when `{staged_files}` is
  referenced and `git diff --cached` returns no files.

  Note that `GitHoox.Runner` already skips hooks whose `:files` glob matches
  nothing, so this guard only fires when `Shell.run/2` is invoked directly
  or when a custom template asks for a file source that the current state
  cannot satisfy.

  ## Timeouts

  Timeouts are enforced by `GitHoox.Runner`, not by this module. A shell
  command exceeding the per-hook `:timeout` is killed brutally and surfaces
  as `{:error, {:timeout, ms}}`. The default timeout is 30 000 ms —
  override per hook via the `:timeout` option in the global hook schema.
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Git
  alias GitHoox.Hooks.Helpers

  @opts_schema [
    run: [
      type: :string,
      required: true,
      doc: "Command template. Supports {files}, {staged_files}, {all_files}, {push_files}."
    ],
    shell: [
      type: :string,
      default: "sh",
      doc: "Shell executable used to run the command."
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
    case Keyword.fetch(opts, :run) do
      {:ok, template} -> run_template(template, files, opts)
      :error -> {:error, "GitHoox.Hooks.Shell requires :run option"}
    end
  end

  defp run_template(template, files, opts) do
    with :ok <- validate_tokens(template, opts) do
      if empty_substitution?(template, files) do
        :ok
      else
        expand_and_exec(template, files, opts)
      end
    end
  end

  defp validate_tokens(template, opts) do
    if uses_token?(template, "{push_files}") and Keyword.get(opts, :__stage__) != :pre_push do
      {:error, "{push_files} token is only valid in the pre_push stage"}
    else
      :ok
    end
  end

  defp empty_substitution?(template, files) do
    files == [] and
      (uses_token?(template, "{files}") or uses_token?(template, "{push_files}"))
  end

  defp expand_and_exec(template, files, opts) do
    case expand(template, files) do
      {:ok, cmd} -> exec(cmd, opts)
      {:skip, _reason} -> :ok
    end
  end

  defp exec(cmd, opts) do
    shell = Keyword.get(opts, :shell, "sh")
    cmd_opts = [stderr_to_stdout: true, env: Helpers.env_opt(opts)]

    case System.cmd(shell, ["-c", cmd], cmd_opts) do
      {_, 0} -> :ok
      {out, code} -> {:error, {code, out}}
    end
  end

  defp expand(template, files) do
    with {:ok, t1} <- replace_files(template, files),
         {:ok, t2} <- replace_push_files(t1, files),
         {:ok, t3} <- replace_staged_files(t2) do
      replace_all_files(t3)
    end
  end

  defp replace_files(template, files) do
    if uses_token?(template, "{files}") do
      {:ok, String.replace(template, "{files}", join(files))}
    else
      {:ok, template}
    end
  end

  defp replace_push_files(template, files) do
    if uses_token?(template, "{push_files}") do
      {:ok, String.replace(template, "{push_files}", join(files))}
    else
      {:ok, template}
    end
  end

  defp replace_staged_files(template) do
    if uses_token?(template, "{staged_files}") do
      case Git.staged_files() do
        {:ok, []} -> {:skip, :no_staged_files}
        {:ok, staged} -> {:ok, String.replace(template, "{staged_files}", join(staged))}
        _ -> {:ok, template}
      end
    else
      {:ok, template}
    end
  end

  defp replace_all_files(template) do
    if uses_token?(template, "{all_files}") do
      case Git.all_files() do
        {:ok, all} -> {:ok, String.replace(template, "{all_files}", join(all))}
        _ -> {:ok, template}
      end
    else
      {:ok, template}
    end
  end

  defp uses_token?(template, token), do: String.contains?(template, token)

  defp join(files), do: Enum.map_join(files, " ", &shell_escape/1)

  defp shell_escape(path), do: "'" <> String.replace(path, "'", "'\\''") <> "'"
end
