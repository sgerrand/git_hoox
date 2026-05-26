defmodule GitHoox.Hooks.Shell do
  @moduledoc """
  Escape hatch for arbitrary shell commands.

  ## Options

    * `:run` — command string. Required. Supports template variables:
      * `{staged_files}` — space-separated staged paths
      * `{all_files}` — all tracked paths
      * `{files}` — space-separated paths passed to the hook
    * `:shell` — shell executable. Default `"sh"`.

  ## Defaults

    * `stage_fixed: false`
  """

  @behaviour GitHoox.Hook

  alias GitHoox.Hooks.Helpers

  @opts_schema [
    run: [
      type: :string,
      required: true,
      doc: "Command template. Supports {staged_files}, {all_files}, {files}."
    ],
    shell: [
      type: :string,
      default: "sh",
      doc: "Shell executable used to run the command."
    ]
  ]

  @impl true
  @spec default_opts() :: keyword()
  def default_opts, do: [stage_fixed: false]

  @impl true
  @spec opts_schema() :: keyword()
  def opts_schema, do: @opts_schema

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run(files, opts) do
    case Keyword.fetch(opts, :run) do
      {:ok, template} ->
        cmd = expand(template, files)
        shell = Keyword.get(opts, :shell, "sh")
        cmd_opts = [stderr_to_stdout: true, env: Helpers.env_opt(opts)]

        case System.cmd(shell, ["-c", cmd], cmd_opts) do
          {_, 0} -> :ok
          {out, code} -> {:error, {code, out}}
        end

      :error ->
        {:error, "GitHoox.Hooks.Shell requires :run option"}
    end
  end

  defp expand(template, files) do
    joined = Enum.map_join(files, " ", &shell_escape/1)

    template
    |> String.replace("{files}", joined)
    |> String.replace("{staged_files}", joined)
    |> replace_all_files()
  end

  defp replace_all_files(template) do
    if String.contains?(template, "{all_files}") do
      {:ok, all} = GitHoox.Git.all_files()
      joined = Enum.map_join(all, " ", &shell_escape/1)
      String.replace(template, "{all_files}", joined)
    else
      template
    end
  end

  defp shell_escape(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end
end
