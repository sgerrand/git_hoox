defmodule GitHoox.Runner do
  @moduledoc """
  Execute hooks for a given stage.

  Resolves staged files, filters per hook's `:files` glob, dispatches
  serially or in parallel based on config, and re-stages mutated files
  when `stage_fixed: true`.
  """

  alias GitHoox.{Config, Git}

  @typedoc "One hook's exit summary."
  @type hook_outcome :: {module(), GitHoox.hook_result()}

  @doc """
  Run all hooks configured for `stage`.

  Returns `:ok` if all hooks succeed (or skip). Returns `{:error, failures}`
  listing modules that failed and their reasons.
  """
  @spec run(GitHoox.stage()) :: :ok | {:error, [hook_outcome()]}
  def run(stage) do
    with {:ok, config} <- Config.load(),
         entries = Keyword.get(config.hooks, stage, []),
         {:ok, files} <- staged(stage),
         entries = filter_skipped(entries, config.skip_env) do
      execute(entries, files, config)
    else
      {:error, reason} ->
        IO.puts(:stderr, GitHoox.Config.Error.format(reason))
        {:error, [{:config, reason}]}
    end
  end

  defp staged(:pre_commit), do: Git.staged_files()
  defp staged(_), do: Git.all_files()

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
      matched
      |> mod.run(opts)
      |> maybe_restage(opts)
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
