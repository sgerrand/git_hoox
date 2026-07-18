defmodule Mix.Tasks.GitHoox.Run do
  @shortdoc "Run git_hoox for a given stage (called from shim)"

  @moduledoc """
  Execute git_hoox for a given stage.

      mix git_hoox.run pre-commit

  Invoked by `.git/hooks/<stage>` shims. Not usually run directly.
  Stage names use kebab-case to match git's hook filenames; they are
  converted to atoms internally.

  ## Output

  Attaches `GitHoox.Reporter` to print coloured hook status to the
  terminal. Turn it off with `config :git_hoox, reporter: false`. Colour
  follows `GIT_HOOX_COLOR` (`always`/`never`), `NO_COLOR`, and
  `CLICOLOR_FORCE`/`FORCE_COLOR`, and otherwise turns on only on a TTY.
  """

  use Mix.Task

  alias GitHoox.Config.Error, as: ConfigError
  alias GitHoox.Config.Schema

  @impl Mix.Task
  @spec run([String.t()]) :: :ok | no_return()
  def run([stage | args]) do
    atom = parse_stage!(stage)
    stdin = read_stdin(atom)
    maybe_attach_reporter()

    case GitHoox.run(atom, args, stdin) do
      :ok ->
        :ok

      {:error, failures} ->
        Enum.each(failures, &print_failure/1)
        exit({:shutdown, 1})
    end
  end

  def run([]), do: Mix.raise("Usage: mix git_hoox.run <stage>")

  # The task runs without the app (and so without :telemetry) started.
  # :telemetry.span/execute tolerate that and simply reach no handlers,
  # but :telemetry.attach needs the app up — and the reporter needs it up
  # to receive events at all. Start it first, and never let a hiccup here
  # block the commit: reporting is cosmetic.
  defp maybe_attach_reporter do
    if Application.get_env(:git_hoox, :reporter, true) and telemetry_started?() do
      GitHoox.Reporter.attach()
    end
  end

  defp telemetry_started? do
    match?({:ok, _}, Application.ensure_all_started(:telemetry))
  end

  defp parse_stage!(stage) do
    case Schema.parse_stage(stage) do
      {:ok, atom} ->
        atom

      :error ->
        valid = Schema.valid_stages()

        Mix.raise(
          "Unknown git_hoox stage: #{stage}. Valid: " <>
            Enum.map_join(valid, ", ", &(&1 |> Atom.to_string() |> String.replace("_", "-")))
        )
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

  defp print_failure({:stage, {:error, {:missing_args, stage}}}) do
    IO.puts(
      :stderr,
      "git_hoox: stage #{stage} invoked without expected arguments from git"
    )
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
end
