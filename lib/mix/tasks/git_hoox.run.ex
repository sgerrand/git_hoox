defmodule Mix.Tasks.GitHoox.Run do
  @shortdoc "Run git_hoox for a given stage (called from shim)"

  @moduledoc """
  Execute git_hoox for a given stage.

      mix git_hoox.run pre-commit

  Invoked by `.git/hooks/<stage>` shims. Not usually run directly.
  Stage names use kebab-case to match git's hook filenames; they are
  converted to atoms internally.
  """

  use Mix.Task

  @impl Mix.Task
  @spec run([String.t()]) :: :ok | no_return()
  def run([stage | _rest]) do
    atom = stage |> String.replace("-", "_") |> String.to_atom()

    case GitHoox.run(atom) do
      :ok ->
        :ok

      {:error, failures} ->
        Enum.each(failures, &print_failure/1)
        exit({:shutdown, 1})
    end
  end

  def run([]), do: Mix.raise("Usage: mix git_hoox.run <stage>")

  defp print_failure({mod, {:error, {code, out}}}) do
    IO.puts(:stderr, "#{inspect(mod)} failed (exit #{code}):\n#{out}")
  end

  defp print_failure({mod, {:error, reason}}) do
    IO.puts(:stderr, "#{inspect(mod)} failed: #{inspect(reason)}")
  end

  defp print_failure(other) do
    IO.puts(:stderr, "Hook failure: #{inspect(other)}")
  end
end
