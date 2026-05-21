defmodule Mix.Tasks.GitHoox.Install do
  @shortdoc "Install git_hoox shims into .git/hooks/"

  @moduledoc """
  Install git_hoox shims.

      mix git_hoox.install            # refuse if user hook exists
      mix git_hoox.install --force    # backup + overwrite
      mix git_hoox.install --dry-run  # plan only

  Detects `core.hooksPath` and worktrees via `git rev-parse --git-path hooks`.
  """

  use Mix.Task

  @switches [force: :boolean, dry_run: :boolean]
  @aliases [f: :force, n: :dry_run]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    case GitHoox.Installer.install(opts) do
      {:ok, plan} -> report(plan, opts)
      {:error, reason} -> Mix.raise(format_error(reason))
    end
  end

  defp report(plan, opts) do
    if Keyword.get(opts, :dry_run, false) do
      Enum.each(plan, &print_plan_entry/1)
    else
      Mix.shell().info("git_hoox installed (#{length(plan)} shims)")
    end

    :ok
  end

  defp print_plan_entry({_hook, path, action}) do
    Mix.shell().info("[#{action}] #{path}")
  end

  defp format_error({:exists, path, msg}), do: "#{msg}\n  #{path}"
  defp format_error(:not_a_git_repo), do: "Not inside a git repository."
end
