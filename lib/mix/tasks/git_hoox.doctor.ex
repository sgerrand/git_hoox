defmodule Mix.Tasks.GitHoox.Doctor do
  @shortdoc "Diagnose a git_hoox installation"

  @moduledoc """
  Run a set of checks against the current repo's git_hoox setup.

      mix git_hoox.doctor

  Each check prints `[ok]`, `[warn]`, or `[fail]` followed by a brief
  detail. Exits 1 if any check is an error, 0 otherwise (warnings do not
  fail the task — they are reminders).
  """

  use Mix.Task

  alias GitHoox.Doctor

  @impl Mix.Task
  @spec run([String.t()]) :: :ok | no_return()
  def run(_argv) do
    checks = Doctor.run()
    Enum.each(checks, &print/1)

    case Doctor.aggregate(checks) do
      :error -> exit({:shutdown, 1})
      _ -> :ok
    end
  end

  defp print(%{name: name, status: status, detail: detail}) do
    Mix.shell().info("#{label(status)} #{name} — #{detail}")
  end

  defp label(:ok), do: "[ok]  "
  defp label(:warn), do: "[warn]"
  defp label(:error), do: "[fail]"
end
