defmodule GitHoox.Bench do
  @moduledoc """
  Benchmark each hook in the resolved configuration over N runs.

  `Bench.run/2` attaches a `:telemetry` handler on
  `[:git_hoox, :hook, :stop]`, dispatches `GitHoox.Runner.run(stage)` the
  requested number of times, and aggregates per-module durations into a
  summary list sorted by total time. Useful for deciding whether a hook is
  cheap enough for `pre_commit` or belongs on `pre_push`.

  Hook exceptions are collected too, since `:exception` events carry a
  duration as well. They are reported in a separate `:errors` count so the
  caller can spot hooks that crashed during the run.
  """

  alias GitHoox.Runner

  @typedoc "Aggregated stats for one hook module, all durations in milliseconds."
  @type summary :: %{
          module: module(),
          runs: non_neg_integer(),
          errors: non_neg_integer(),
          p50_ms: number(),
          p95_ms: number(),
          max_ms: number(),
          mean_ms: number(),
          total_ms: number()
        }

  @doc "Sample `Runner.run(stage)` `runs` times and return a per-module summary."
  @spec run(GitHoox.stage(), pos_integer()) :: [summary()]
  def run(stage, runs) when is_integer(runs) and runs > 0 do
    {handler_id, agent} = attach_collector()

    try do
      Enum.each(1..runs, fn _ -> Runner.run(stage) end)

      agent
      |> Agent.get(& &1)
      |> summarize()
    after
      :telemetry.detach(handler_id)
      Agent.stop(agent)
    end
  end

  @doc false
  @spec summarize(%{module() => {[integer()], non_neg_integer()}}) :: [summary()]
  def summarize(samples) when is_map(samples) do
    samples
    |> Enum.map(fn {mod, {natives, errors}} -> summary_for(mod, natives, errors) end)
    |> Enum.sort_by(& &1.total_ms, :desc)
  end

  defp summary_for(mod, natives, errors) do
    ms_list = natives |> Enum.map(&to_ms/1) |> Enum.sort()
    n = length(ms_list)

    %{
      module: mod,
      runs: n,
      errors: errors,
      p50_ms: percentile(ms_list, 50),
      p95_ms: percentile(ms_list, 95),
      max_ms: List.last(ms_list) || 0,
      mean_ms: if(n > 0, do: Enum.sum(ms_list) / n, else: 0),
      total_ms: Enum.sum(ms_list)
    }
  end

  defp attach_collector do
    {:ok, agent} = Agent.start_link(fn -> %{} end)
    handler_id = "git_hoox.bench-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [
        [:git_hoox, :hook, :stop],
        [:git_hoox, :hook, :exception]
      ],
      &__MODULE__.handle/4,
      agent
    )

    {handler_id, agent}
  end

  @doc false
  def handle([:git_hoox, :hook, :stop], %{duration: d}, %{module: mod, result: result}, agent) do
    record(agent, mod, d, result == :error)
  end

  def handle([:git_hoox, :hook, :exception], %{duration: d}, %{module: mod}, agent) do
    record(agent, mod, d, true)
  end

  defp record(agent, mod, duration, error?) do
    bump = if error?, do: 1, else: 0

    Agent.update(agent, fn map ->
      Map.update(map, mod, {[duration], bump}, fn {natives, errs} ->
        {[duration | natives], errs + bump}
      end)
    end)
  end

  defp percentile([], _pct), do: 0

  defp percentile(sorted, pct) do
    idx = trunc(length(sorted) * pct / 100)
    Enum.at(sorted, min(idx, length(sorted) - 1))
  end

  defp to_ms(native), do: System.convert_time_unit(native, :native, :millisecond)
end
