defmodule GitHoox.Telemetry do
  @moduledoc """
  `:telemetry` event emission for GitHoox.

  GitHoox emits two pairs of `:telemetry` events: one around each stage, one
  around each individual hook invocation. Events are emitted unconditionally;
  no handler is attached by default. Attach `GitHoox.Reporter` for coloured
  terminal status, `GitHoox.Logger` for `Logger`-backed output, or attach
  your own handler for custom routing.

  ## Events

  ### `[:git_hoox, :stage, :start | :stop | :exception]`

  Wraps a stage run from `GitHoox.Runner.run/3`.

    * `:start` measurements — `%{system_time: integer()}`
    * `:stop` measurements  — `%{duration: integer()}` (native time units)
    * Metadata (`:start` and `:stop`) — `%{stage: atom(), entries: non_neg_integer(), files: non_neg_integer()}`
    * `:stop` metadata also carries `%{result: :ok | :error, failures: non_neg_integer()}`

  ### `[:git_hoox, :hook, :start | :stop | :exception]`

  Wraps a single hook invocation.

    * Measurements as for the stage events.
    * Metadata — `%{stage: atom(), module: module(), files: non_neg_integer()}`
    * `:stop` metadata also carries `%{result: :ok | :error, error: term() | nil}`

  ### `[:git_hoox, :hook, :skip]`

  Fired in place of the `:start`/`:stop` pair when a hook's `:files` glob
  filters all candidate files out. Single event, no span — skipped hooks
  do not run and have no measurable duration.

    * Measurements — `%{system_time: integer()}`
    * Metadata — `%{stage: atom(), module: module(), files: 0}`

  ## Example handler

      :telemetry.attach(
        "my-hook-logger",
        [:git_hoox, :hook, :stop],
        fn _event, %{duration: d}, %{module: mod, result: r}, _ ->
          ms = System.convert_time_unit(d, :native, :millisecond)
          IO.puts("\#{inspect(mod)} → \#{r} in \#{ms}ms")
        end,
        nil
      )

  """

  @stage [:git_hoox, :stage]
  @hook [:git_hoox, :hook]

  @doc false
  @spec stage_span(atom(), non_neg_integer(), non_neg_integer(), (-> result)) :: result
        when result: term()
  def stage_span(stage, entries, files, fun) do
    base = %{stage: stage, entries: entries, files: files}

    :telemetry.span(@stage, base, fn ->
      result = fun.()
      {result, Map.merge(base, stop_metadata(result))}
    end)
  end

  @doc false
  @spec hook_span(atom(), module(), non_neg_integer(), (-> result)) :: result
        when result: term()
  def hook_span(stage, module, files, fun) do
    base = %{stage: stage, module: module, files: files}

    :telemetry.span(@hook, base, fn ->
      result = fun.()
      {result, Map.merge(base, hook_stop_metadata(result))}
    end)
  end

  @doc false
  @spec hook_skip(atom(), module()) :: :ok
  def hook_skip(stage, module) do
    :telemetry.execute(
      @hook ++ [:skip],
      %{system_time: System.system_time()},
      %{stage: stage, module: module, files: 0}
    )
  end

  defp stop_metadata(:ok), do: %{result: :ok, failures: 0}

  defp stop_metadata({:error, failures}) when is_list(failures),
    do: %{result: :error, failures: length(failures)}

  defp stop_metadata(_), do: %{result: :error, failures: 1}

  defp hook_stop_metadata(:ok), do: %{result: :ok, error: nil}
  defp hook_stop_metadata({:ok, _modified}), do: %{result: :ok, error: nil}
  defp hook_stop_metadata(:skip), do: %{result: :skip, error: nil}
  defp hook_stop_metadata({:error, reason}), do: %{result: :error, error: reason}
end
