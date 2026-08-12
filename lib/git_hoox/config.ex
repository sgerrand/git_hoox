defmodule GitHoox.Config do
  @moduledoc """
  Load and validate `.git_hoox.exs`.

  Validation uses [NimbleOptions](https://hexdocs.pm/nimble_options). Errors
  surface as `{:error, reason}` where `reason` is formattable via
  `GitHoox.Config.Error.format/1`.
  """

  alias GitHoox.Config.Schema
  alias GitHoox.Hook

  @type load_error :: GitHoox.Config.Error.t()

  @default_path ".git_hoox.exs"

  @doc "Default config path relative to repo root."
  @spec default_path() :: Path.t()
  def default_path, do: @default_path

  @doc """
  Load and validate config from `path`.
  """
  @spec load(Path.t()) :: {:ok, GitHoox.config()} | {:error, load_error()}
  def load(path \\ @default_path) do
    with {:ok, raw} <- read_file(path),
         {:ok, top} <- validate_top(raw),
         {:ok, top} <- validate_stages(top),
         {:ok, top} <- validate_hook_entries(top) do
      {:ok, Map.new(top)}
    end
  end

  defp read_file(path) do
    if File.exists?(path) do
      eval_config(path)
    else
      {:error, {:missing_config, path}}
    end
  end

  defp eval_config(path) do
    {raw, _binding} = Code.eval_file(path)
    normalize(raw)
  rescue
    err ->
      {:error, {:invalid_config, "failed to evaluate #{path}: #{Exception.message(err)}"}}
  catch
    kind, reason ->
      {:error, {:invalid_config, "failed to evaluate #{path}: #{kind}: #{inspect(reason)}"}}
  end

  defp normalize(raw) when is_map(raw), do: {:ok, Map.to_list(raw)}
  defp normalize(raw) when is_list(raw), do: {:ok, raw}

  defp normalize(raw) do
    {:error,
     {:invalid_config, "expected config to return a map or keyword list, got: #{inspect(raw)}"}}
  end

  @global_keys Schema.hook_opts_schema() |> Keyword.keys()

  defp validate_top(raw) do
    case NimbleOptions.validate(raw, Schema.top_schema()) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, %NimbleOptions.ValidationError{} = err} ->
        {:error, {:invalid_config, Exception.message(err)}}
    end
  end

  defp validate_stages(top) do
    bad =
      top[:hooks]
      |> Keyword.keys()
      |> Enum.reject(&(&1 in Schema.valid_stages()))

    case bad do
      [] -> {:ok, top}
      _ -> {:error, {:invalid_stages, bad, Schema.valid_stages()}}
    end
  end

  # Map `fun` over `enum`, collecting `{:ok, value}` results and halting on
  # the first error, which is returned as-is.
  defp map_ok(enum, fun) do
    Enum.reduce_while(enum, [], fn item, acc ->
      case fun.(item) do
        {:ok, value} -> {:cont, [value | acc]}
        err -> {:halt, err}
      end
    end)
    |> case do
      acc when is_list(acc) -> {:ok, Enum.reverse(acc)}
      err -> err
    end
  end

  defp validate_hook_entries(top) do
    result =
      map_ok(top[:hooks], fn {stage, entries} ->
        with {:ok, entries} <- validate_entries(stage, entries), do: {:ok, {stage, entries}}
      end)

    with {:ok, hooks} <- result, do: {:ok, Keyword.put(top, :hooks, hooks)}
  end

  defp validate_entries(stage, entries) when is_list(entries) do
    map_ok(entries, &validate_entry(stage, &1))
  end

  defp validate_entry(stage, {mod, opts}) when is_atom(mod) and is_list(opts) do
    with :ok <- ensure_loaded(stage, mod),
         :ok <- ensure_behaviour(stage, mod),
         {:ok, opts} <- validate_opts(stage, mod, opts) do
      {:ok, {mod, opts}}
    end
  end

  defp validate_entry(stage, other) do
    {:error, {:invalid_hook_entry, stage, other}}
  end

  defp ensure_loaded(stage, mod) do
    if Code.ensure_loaded?(mod) do
      :ok
    else
      {:error, {:invalid_hook_module, stage, mod, "module not loaded"}}
    end
  end

  defp ensure_behaviour(stage, mod) do
    if function_exported?(mod, :run, 2) do
      :ok
    else
      {:error,
       {:invalid_hook_module, stage, mod, "missing run/2 — does it implement GitHoox.Hook?"}}
    end
  end

  defp validate_opts(stage, mod, opts) do
    merged = Hook.merge_defaults(mod, opts)

    with {:ok, global} <- validate_global(stage, mod, merged),
         {:ok, specific} <- validate_hook_specific(stage, mod, merged) do
      {:ok, Keyword.merge(global, specific)}
    end
  end

  defp validate_global(stage, mod, merged) do
    merged
    |> Keyword.take(@global_keys)
    |> validate_with(Schema.hook_opts_schema(), stage, mod)
  end

  defp validate_hook_specific(stage, mod, merged) do
    specific = Keyword.drop(merged, @global_keys)

    if function_exported?(mod, :opts_schema, 0) do
      validate_with(specific, mod.opts_schema(), stage, mod)
    else
      {:ok, specific}
    end
  end

  defp validate_with(opts, schema, stage, mod) do
    case NimbleOptions.validate(opts, schema) do
      {:ok, opts} -> {:ok, opts}
      {:error, err} -> {:error, {:invalid_hook_opts, stage, mod, Exception.message(err)}}
    end
  end
end
