defmodule GitHoox.Runner do
  @moduledoc """
  Execute hooks for a given stage.

  Resolves the file set per stage, filters per hook's `:files` glob,
  dispatches serially or in parallel, enforces per-hook timeouts, and
  re-stages mutated files when `stage_fixed: true`.
  """

  alias GitHoox.Config
  alias GitHoox.Git
  alias GitHoox.Glob
  alias GitHoox.Telemetry

  @typedoc "One hook's exit summary."
  @type hook_outcome :: {module(), GitHoox.hook_result()}

  @doc """
  Run all hooks configured for `stage`.

  `args` are the positional arguments the git shim received (e.g. the
  commit message file path for `commit_msg`). `stdin` is the raw input
  passed to the shim, used for `pre_push`.
  """
  @spec run(GitHoox.stage(), [String.t()], String.t() | nil) ::
          :ok | {:error, [hook_outcome()]}
  def run(stage, args \\ [], stdin \\ nil) do
    with {:ok, config} <- Config.load(),
         {:ok, files} <- files_for_stage(stage, args, stdin) do
      entries =
        config.hooks
        |> Keyword.get(stage, [])
        |> filter_skipped(config.skip_env)

      Telemetry.stage_span(stage, length(entries), length(files), fn ->
        execute(entries, files, config, stage)
      end)
    else
      {:error, {:missing_args, _} = reason} ->
        {:error, [{:stage, {:error, reason}}]}

      {:error, reason} ->
        {:error, [{:config, {:error, reason}}]}
    end
  end

  defp files_for_stage(:pre_commit, _args, _stdin), do: Git.staged_files()
  defp files_for_stage(:commit_msg, [path | _], _), do: {:ok, [path]}
  defp files_for_stage(:commit_msg, _, _), do: {:error, {:missing_args, :commit_msg}}
  defp files_for_stage(:prepare_commit_msg, [path | _], _), do: {:ok, [path]}

  defp files_for_stage(:prepare_commit_msg, _, _),
    do: {:error, {:missing_args, :prepare_commit_msg}}

  defp files_for_stage(:post_commit, _args, _stdin), do: Git.files_in_head()
  defp files_for_stage(:post_merge, _args, _stdin), do: Git.merge_files()
  defp files_for_stage(:post_checkout, [from, to | _], _), do: Git.diff_files(from, to)
  defp files_for_stage(:post_checkout, _, _), do: {:error, {:missing_args, :post_checkout}}
  defp files_for_stage(:pre_rebase, _args, _stdin), do: {:ok, []}
  defp files_for_stage(:pre_push, _args, stdin), do: Git.push_files(stdin)
  defp files_for_stage(_other, _args, _stdin), do: Git.all_files()

  defp filter_skipped(entries, skip_env) do
    cond do
      System.get_env(skip_env) == "0" ->
        []

      excludes = System.get_env(skip_env <> "_EXCLUDE") ->
        names = parse_csv(excludes)
        Enum.reject(entries, fn {mod, _} -> short_name(mod) in names end)

      only = System.get_env(skip_env <> "_ONLY") ->
        names = parse_csv(only)
        Enum.filter(entries, fn {mod, _} -> short_name(mod) in names end)

      true ->
        entries
    end
  end

  defp parse_csv(str) do
    str |> String.split(",", trim: true) |> Enum.map(&String.trim/1)
  end

  defp short_name(mod) do
    mod
    |> Module.split()
    |> List.last()
    |> String.downcase()
  end

  defp execute([], _files, _config, _stage), do: :ok

  defp execute(entries, files, config, stage) do
    results =
      if config.parallel do
        run_parallel(entries, files, config, stage)
      else
        run_serial(entries, files, config, stage)
      end

    failures = Enum.filter(results, &failure?/1)

    case failures do
      [] -> :ok
      _ -> {:error, failures}
    end
  end

  defp run_serial(entries, files, config, stage) do
    entries
    |> Stream.map(fn {mod, _} = entry -> {mod, run_one(entry, files, stage)} end)
    |> collect(config.fail_fast)
  end

  defp run_parallel(entries, files, config, stage) do
    captures = open_captures(entries)

    try do
      entries
      |> Enum.with_index()
      |> Task.async_stream(
        fn {entry, index} ->
          {index, run_with_captured_io(entry, files, stage, captures[index])}
        end,
        max_concurrency: System.schedulers_online(),
        ordered: false,
        timeout: :infinity
      )
      |> Stream.map(fn {:ok, {index, outcome}} ->
        flush_capture(captures[index])
        outcome
      end)
      |> collect(config.fail_fast)
    after
      # A fail_fast halt terminates the hooks still in flight, so they
      # never reach the flush above. Their buffers outlive them because
      # the devices belong to this process rather than to the tasks —
      # drain what they printed before they were cancelled, in
      # configuration order.
      captures
      |> Enum.sort()
      |> Enum.each(fn {_index, device} ->
        flush_capture(device)
        StringIO.close(device)
      end)
    end
  end

  defp open_captures(entries) do
    Map.new(0..(length(entries) - 1), fn index ->
      {:ok, device} = StringIO.open("")
      {index, device}
    end)
  end

  # StringIO.flush/1 empties the buffer as it reads, so flushing a device
  # a second time is a no-op rather than a duplicate print.
  defp flush_capture(device) do
    case StringIO.flush(device) do
      "" -> :ok
      text -> IO.write(text)
    end
  end

  # Both dispatch paths produce a lazy stream of outcomes, so a fail_fast
  # halt stops later hooks being dispatched. What it does to work already
  # underway differs: serially there is none, but in parallel the halt
  # tears down the async_stream, which terminates the hooks still in
  # flight. Cancellation is abrupt — those tasks do not trap exits, so a
  # hook can be interrupted mid-write and its outcome is discarded — but
  # whatever it printed first is still flushed by run_parallel/4.
  # Ordinary hook timeouts are unaffected; they are enforced per hook by
  # invoke_with_timeout!/4, well inside the task.
  defp collect(outcomes, fail_fast?) do
    outcomes
    |> Enum.reduce_while([], fn outcome, acc ->
      acc = [outcome | acc]

      if fail_fast? and failure?(outcome) do
        {:halt, acc}
      else
        {:cont, acc}
      end
    end)
    |> Enum.reverse()
  end

  # Redirect the task's group leader to an in-memory StringIO for the
  # duration of the hook. Without this, parallel hooks interleave each
  # other's stdout chunk-by-chunk on the real device.
  #
  # The device is opened by run_parallel/4 and merely borrowed here, so
  # that a task killed by a fail_fast halt cannot take the buffer with
  # it. Flushing is the caller's job for the same reason: a cancelled
  # task never runs its own `after`.
  defp run_with_captured_io(entry, files, stage, capture) do
    parent_gl = Process.group_leader()
    Process.group_leader(self(), capture)

    try do
      {elem(entry, 0), run_one(entry, files, stage)}
    after
      Process.group_leader(self(), parent_gl)
    end
  end

  defp run_one({mod, user_opts}, files, stage) do
    opts = Keyword.put(user_opts, :__stage__, stage)
    matched = filter_files(files, Keyword.fetch!(opts, :files))

    if matched == [] do
      Telemetry.hook_skip(stage, mod)
      :ok
    else
      timeout = Keyword.get(opts, :timeout, 30_000)
      invoke_traced(matched, mod, opts, timeout, stage)
    end
  end

  # Wraps the hook in a telemetry span that lets :exception events fire
  # naturally on timeout/crash, then catches the propagated exit so the
  # public Runner.run/3 contract continues to return {:error, _} values.
  defp invoke_traced(matched, mod, opts, timeout, stage) do
    Telemetry.hook_span(stage, mod, length(matched), fn ->
      matched
      |> invoke_with_timeout!(mod, opts, timeout)
      |> maybe_restage(opts)
    end)
  catch
    :exit, {:git_hoox_timeout, ms} -> {:error, {:timeout, ms}}
    :exit, reason -> {:error, {:crashed, reason}}
  end

  defp invoke_with_timeout!(files, mod, opts, timeout) do
    # Task.async links the spawned task to the caller. Without trap_exit the
    # link kills this process the instant the hook raises, before Task.yield
    # has a chance to return {:exit, reason}. Trap, restore on the way out.
    prior_trap = Process.flag(:trap_exit, true)

    try do
      task = Task.async(fn -> mod.run(files, opts) end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} -> result
        nil -> exit({:git_hoox_timeout, timeout})
        {:exit, reason} -> exit(reason)
      end
    after
      Process.flag(:trap_exit, prior_trap)
    end
  end

  defp filter_files([], _patterns), do: []

  defp filter_files(files, patterns) do
    regexes = Enum.map(patterns, &Glob.compile/1)
    Enum.filter(files, fn f -> Enum.any?(regexes, &Regex.match?(&1, f)) end)
  end

  # Normalize every accepted hook return to the runner's narrow outcome
  # shape: :ok on success (with optional re-staging side effect) and the
  # original {:error, _} on failure. Anything else is a contract violation
  # and is allowed to FunctionClauseError so the bug surfaces immediately.
  defp maybe_restage(:ok, _opts), do: :ok

  defp maybe_restage({:ok, modified}, opts) when is_list(modified) do
    if Keyword.get(opts, :stage_fixed, false) and modified != [] do
      Git.restage(modified)
    end

    :ok
  end

  defp maybe_restage({:error, _} = err, _opts), do: err

  defp failure?({_mod, {:error, _}}), do: true
  defp failure?(_), do: false
end
