defmodule Mix.Tasks.GitHoox.Bench do
  @shortdoc "Benchmark each hook over N runs and print percentiles"

  @moduledoc """
  Run the configured hooks for a stage repeatedly and report timing
  statistics per hook.

      mix git_hoox.bench                      # pre_commit, 5 runs
      mix git_hoox.bench --stage pre_push     # different stage
      mix git_hoox.bench --runs 20            # more samples
      mix git_hoox.bench -s commit-msg -n 3   # short flags

  Reads the resolved configuration just like a real hook invocation, so
  any hook that needs files (e.g. `Format` filtering on staged Elixir
  files) needs at least one matching file present for the timing to be
  meaningful. Hooks that crash count against the `errors` column but
  their duration still contributes to the percentiles.
  """

  use Mix.Task

  alias GitHoox.Bench

  @switches [stage: :string, runs: :integer]
  @aliases [s: :stage, n: :runs]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    stage =
      opts
      |> Keyword.get(:stage, "pre_commit")
      |> String.replace("-", "_")
      |> String.to_atom()

    runs = Keyword.get(opts, :runs, 5)

    Mix.shell().info("Benchmarking #{stage} (#{runs} runs)...")
    Mix.shell().info("")

    stage
    |> Bench.run(runs)
    |> print()

    :ok
  end

  defp print([]) do
    Mix.shell().info("(no hooks executed)")
  end

  defp print(results) do
    Mix.shell().info(header())
    Mix.shell().info(separator())
    Enum.each(results, &print_row/1)
  end

  defp header do
    "#{pad("module", 36)} #{pad("runs", 5)} #{pad("errors", 6)} #{pad("p50", 9)} #{pad("p95", 9)} #{pad("max", 9)} #{pad("mean", 9)} #{pad("total", 9)}"
  end

  defp separator do
    String.duplicate("-", 36) <>
      " " <>
      String.duplicate("-", 5) <>
      " " <>
      String.duplicate("-", 6) <>
      " " <>
      String.duplicate("-", 9) <>
      " " <>
      String.duplicate("-", 9) <>
      " " <>
      String.duplicate("-", 9) <>
      " " <>
      String.duplicate("-", 9) <>
      " " <> String.duplicate("-", 9)
  end

  defp print_row(r) do
    Mix.shell().info(
      "#{pad(inspect(r.module), 36)} #{pad_int(r.runs, 5)} #{pad_int(r.errors, 6)} " <>
        "#{pad_ms(r.p50_ms, 9)} #{pad_ms(r.p95_ms, 9)} #{pad_ms(r.max_ms, 9)} " <>
        "#{pad_ms(r.mean_ms, 9)} #{pad_ms(r.total_ms, 9)}"
    )
  end

  defp pad(s, w), do: String.pad_trailing(s, w)
  defp pad_int(n, w), do: String.pad_leading(Integer.to_string(n), w)

  defp pad_ms(ms, w) do
    String.pad_leading("#{round_ms(ms)}ms", w)
  end

  defp round_ms(ms) when is_integer(ms), do: ms
  defp round_ms(ms) when is_float(ms), do: Float.round(ms, 1)
end
