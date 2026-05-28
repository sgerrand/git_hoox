defmodule Mix.Tasks.GitHoox.Install do
  @shortdoc "Install git_hoox shims into .git/hooks/"

  @moduledoc """
  Install git_hoox shims.

      mix git_hoox.install              # refuse if user hook exists
      mix git_hoox.install --force      # backup + overwrite shims (and config)
      mix git_hoox.install --dry-run    # plan only, write nothing
      mix git_hoox.install --scaffold   # also write a starter .git_hoox.exs

  Detects `core.hooksPath` and worktrees via `git rev-parse --git-path hooks`.
  """

  use Mix.Task

  @switches [force: :boolean, dry_run: :boolean, scaffold: :boolean]
  @aliases [f: :force, n: :dry_run, s: :scaffold]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    case GitHoox.Installer.install(opts) do
      {:ok, plan} ->
        report(plan, opts)
        maybe_scaffold(opts)
        :ok

      {:error, reason} ->
        Mix.raise(format_error(reason))
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

  defp maybe_scaffold(opts) do
    cond do
      not Keyword.get(opts, :scaffold, false) ->
        :ok

      Keyword.get(opts, :dry_run, false) ->
        Mix.shell().info("[scaffold] .git_hoox.exs (dry-run, not written)")
        :ok

      true ->
        case GitHoox.Installer.scaffold(opts) do
          {:ok, path} ->
            Mix.shell().info("git_hoox: wrote #{path}")

          {:error, {:config_exists, path}} ->
            Mix.shell().error("git_hoox: #{path} already exists. Re-run with --force to overwrite.")

          {:error, {code, out}} when is_integer(code) ->
            Mix.raise("git_hoox scaffold failed: git exited #{code}\n#{out}")
        end
    end
  end

  defp format_error({:exists, path, msg}), do: "#{msg}\n  #{path}"
  defp format_error(other), do: "git_hoox install failed: #{inspect(other)}"
end
