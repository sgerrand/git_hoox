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
  alias GitHoox.Config.Schema

  @switches [stage: :string, runs: :integer]
  @aliases [s: :stage, n: :runs]

  @cols [
    {"module", 36, :left},
    {"runs", 5, :right},
    {"errors", 6, :right},
    {"p50", 9, :right},
    {"p95", 9, :right},
    {"max", 9, :right},
    {"mean", 9, :right},
    {"total", 9, :right}
  ]

  @impl Mix.Task
  @spec run([String.t()]) :: :ok
  def run(argv) do
    {opts, _, _} = OptionParser.parse(argv, switches: @switches, aliases: @aliases)

    stage = parse_stage!(Keyword.get(opts, :stage, "pre_commit"))
    runs = Keyword.get(opts, :runs, 5)

    Mix.shell().info("Benchmarking #{stage} (#{runs} runs)...")
    Mix.shell().info("")

    stage
    |> Bench.run(runs)
    |> print()

    :ok
  end

  defp parse_stage!(stage) do
    case Schema.parse_stage(stage) do
      {:ok, atom} -> atom
      :error -> Mix.raise("Unknown git_hoox stage: #{stage}")
    end
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
    Enum.map_join(@cols, " ", fn {label, w, _} -> String.pad_trailing(label, w) end)
  end

  defp separator do
    Enum.map_join(@cols, " ", fn {_, w, _} -> String.duplicate("-", w) end)
  end

  defp print_row(r) do
    [
      inspect(r.module),
      Integer.to_string(r.runs),
      Integer.to_string(r.errors),
      format_ms(r.p50_ms),
      format_ms(r.p95_ms),
      format_ms(r.max_ms),
      format_ms(r.mean_ms),
      format_ms(r.total_ms)
    ]
    |> Enum.zip(@cols)
    |> Enum.map_join(" ", fn {val, {_, w, align}} -> pad(val, w, align) end)
    |> Mix.shell().info()
  end

  defp pad(s, w, :left), do: String.pad_trailing(s, w)
  defp pad(s, w, :right), do: String.pad_leading(s, w)

  defp format_ms(ms) when is_integer(ms), do: "#{ms}ms"
  defp format_ms(ms) when is_float(ms), do: "#{Float.round(ms, 1)}ms"
end
