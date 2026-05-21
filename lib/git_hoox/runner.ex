defmodule GitHoox.Runner do
  @moduledoc """
  Execute hooks for a given stage.

  Resolves the file set per stage, filters per hook's `:files` glob,
  dispatches serially or in parallel, enforces per-hook timeouts, and
  re-stages mutated files when `stage_fixed: true`.
  """

  alias GitHoox.Config
  alias GitHoox.Config.Error, as: ConfigError
  alias GitHoox.Git

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

      execute(entries, files, config)
    else
      {:error, reason} ->
        IO.puts(:stderr, ConfigError.format(reason))
        {:error, [{:config, reason}]}
    end
  end

  defp files_for_stage(:pre_commit, _args, _stdin), do: Git.staged_files()
  defp files_for_stage(:commit_msg, [path | _], _), do: {:ok, [path]}
  defp files_for_stage(:prepare_commit_msg, [path | _], _), do: {:ok, [path]}
  defp files_for_stage(:post_commit, _args, _stdin), do: Git.files_in_head()
  defp files_for_stage(:post_merge, _args, _stdin), do: Git.merge_files()
  defp files_for_stage(:post_checkout, [from, to | _], _), do: Git.diff_files(from, to)
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

  defp execute([], _files, _config), do: :ok

  defp execute(entries, files, config) do
    results =
      if config.parallel do
        run_parallel(entries, files, config)
      else
        run_serial(entries, files, config)
      end

    failures = Enum.filter(results, &failure?/1)

    case failures do
      [] -> :ok
      _ -> {:error, failures}
    end
  end

  defp run_serial(entries, files, config) do
    Enum.reduce_while(entries, [], fn entry, acc ->
      result = run_one(entry, files)
      acc = [{elem(entry, 0), result} | acc]

      if config.fail_fast and failure?({elem(entry, 0), result}) do
        {:halt, Enum.reverse(acc)}
      else
        {:cont, acc}
      end
    end)
    |> case do
      list when is_list(list) -> Enum.reverse(list)
    end
  end

  defp run_parallel(entries, files, _config) do
    entries
    |> Task.async_stream(
      fn entry -> {elem(entry, 0), run_one(entry, files)} end,
      max_concurrency: System.schedulers_online(),
      ordered: true,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, outcome} -> outcome end)
  end

  defp run_one({mod, user_opts}, files) do
    opts = merge_defaults(mod, user_opts)
    matched = filter_files(files, Keyword.fetch!(opts, :files))

    if matched == [] do
      :skip
    else
      timeout = Keyword.get(opts, :timeout, 30_000)

      matched
      |> invoke_with_timeout(mod, opts, timeout)
      |> maybe_restage(opts)
    end
  end

  defp invoke_with_timeout(files, mod, opts, timeout) do
    task = Task.async(fn -> mod.run(files, opts) end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, {:timeout, timeout}}
      {:exit, reason} -> {:error, {:crashed, reason}}
    end
  end

  defp merge_defaults(mod, user_opts) do
    defaults =
      if function_exported?(mod, :default_opts, 0),
        do: mod.default_opts(),
        else: []

    Keyword.merge(defaults, user_opts)
  end

  defp filter_files(files, patterns) do
    Enum.filter(files, fn f -> Enum.any?(patterns, &match_glob?(&1, f)) end)
  end

  defp match_glob?(pattern, file) do
    regex =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*/", "(?:.*/)?")
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> String.replace("\\?", "[^/]")

    Regex.match?(~r/\A#{regex}\z/, file)
  end

  defp maybe_restage({:ok, modified}, opts) when is_list(modified) do
    if Keyword.get(opts, :stage_fixed, false) and modified != [] do
      Git.restage(modified)
    end

    :ok
  end

  defp maybe_restage(other, _opts), do: other

  defp failure?({_mod, {:error, _}}), do: true
  defp failure?(_), do: false
end
