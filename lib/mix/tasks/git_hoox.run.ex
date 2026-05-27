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

  alias GitHoox.Config.Error, as: ConfigError
  alias GitHoox.Config.Schema

  @impl Mix.Task
  @spec run([String.t()]) :: :ok | no_return()
  def run([stage | args]) do
    atom = parse_stage!(stage)
    stdin = read_stdin(atom)

    case GitHoox.run(atom, args, stdin) do
      :ok ->
        :ok

      {:error, failures} ->
        Enum.each(failures, &print_failure/1)
        exit({:shutdown, 1})
    end
  end

  def run([]), do: Mix.raise("Usage: mix git_hoox.run <stage>")

  defp parse_stage!(stage) do
    atom_name = String.replace(stage, "-", "_")
    valid = Schema.valid_stages()

    case Enum.find(valid, fn s -> Atom.to_string(s) == atom_name end) do
      nil ->
        Mix.raise(
          "Unknown git_hoox stage: #{stage}. Valid: " <>
            Enum.map_join(valid, ", ", &(&1 |> Atom.to_string() |> String.replace("_", "-")))
        )

      atom ->
        atom
    end
  end

  defp read_stdin(:pre_push) do
    case IO.read(:stdio, :eof) do
      :eof -> nil
      data when is_binary(data) -> data
    end
  end

  defp read_stdin(_), do: nil

  defp print_failure({:config, {:error, reason}}) do
    IO.puts(:stderr, ConfigError.format(reason))
  end

  defp print_failure({mod, {:error, {:timeout, ms}}}) do
    IO.puts(:stderr, "#{inspect(mod)} timed out after #{ms}ms")
  end

  defp print_failure({mod, {:error, {:crashed, reason}}}) do
    IO.puts(:stderr, "#{inspect(mod)} crashed: #{inspect(reason)}")
  end

  defp print_failure({mod, {:error, {code, out}}}) when is_integer(code) do
    IO.puts(:stderr, "#{inspect(mod)} failed (exit #{code}):\n#{out}")
  end

  defp print_failure({mod, {:error, reason}}) do
    IO.puts(:stderr, "#{inspect(mod)} failed: #{inspect(reason)}")
  end

  defp print_failure(other) do
    IO.puts(:stderr, "Hook failure: #{inspect(other)}")
  end
end
