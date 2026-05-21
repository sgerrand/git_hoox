defmodule GitHoox.Config do
  @moduledoc """
  Load and validate `.git_hoox.exs`.

  Validation uses [NimbleOptions](https://hexdocs.pm/nimble_options). Errors
  surface as `{:error, reason}` where `reason` is formattable via
  `GitHoox.Config.Error.format/1`.
  """

  alias GitHoox.Config.Schema

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
      {raw, _binding} = Code.eval_file(path)
      {:ok, normalize(raw)}
    else
      {:error, {:missing_config, path}}
    end
  end

  defp normalize(raw) when is_map(raw), do: Map.to_list(raw)
  defp normalize(raw) when is_list(raw), do: raw

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

  defp validate_hook_entries(top) do
    Enum.reduce_while(top[:hooks], {:ok, top}, fn {stage, entries}, acc ->
      case validate_entries(stage, entries) do
        :ok -> {:cont, acc}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_entries(stage, entries) when is_list(entries) do
    Enum.reduce_while(entries, :ok, fn entry, _ ->
      case validate_entry(stage, entry) do
        :ok -> {:cont, :ok}
        err -> {:halt, err}
      end
    end)
  end

  defp validate_entry(stage, {mod, opts}) when is_atom(mod) and is_list(opts) do
    with :ok <- ensure_loaded(stage, mod),
         :ok <- ensure_behaviour(stage, mod),
         :ok <- validate_opts(stage, mod, opts) do
      :ok
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
    merged = merge_defaults(mod, opts)
    known = Schema.hook_opts_schema() |> Keyword.keys()
    to_validate = Keyword.take(merged, known)

    case NimbleOptions.validate(to_validate, Schema.hook_opts_schema()) do
      {:ok, _} ->
        :ok

      {:error, %NimbleOptions.ValidationError{} = err} ->
        {:error, {:invalid_hook_opts, stage, mod, Exception.message(err)}}
    end
  end

  defp merge_defaults(mod, opts) do
    defaults =
      if function_exported?(mod, :default_opts, 0),
        do: mod.default_opts(),
        else: []

    Keyword.merge(defaults, opts)
  end
end
