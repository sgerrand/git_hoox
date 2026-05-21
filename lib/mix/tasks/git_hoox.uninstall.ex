defmodule Mix.Tasks.GitHoox.Uninstall do
  @shortdoc "Remove git_hoox shims from .git/hooks/"

  @moduledoc """
  Remove only the shims git_hoox installed (identified by marker comment).
  Restores the most recent `.backup.*` for each removed shim if present.
  """

  use Mix.Task

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(_argv) do
    case GitHoox.Installer.uninstall() do
      {:ok, count} ->
        Mix.shell().info("git_hoox: removed #{count} shim(s)")
        :ok

      {:error, reason} ->
        Mix.raise(inspect(reason))
    end
  end
end
