defmodule GitHoox.Logger do
  @moduledoc """
  Reference `:telemetry` handler that logs GitHoox events via `Logger`.

  Attach during application start or before invoking hooks:

      GitHoox.Logger.attach()

  Detach with `GitHoox.Logger.detach/0`. The handler is opt-in; GitHoox does
  not attach it for you.

  Log lines look like:

      [git_hoox] pre_commit → ok (2 hooks, 3 files, 240ms)
      [git_hoox]   GitHoox.Hooks.Format → ok (240ms)
      [git_hoox]   GitHoox.Hooks.Credo → error (1.5s) reason: {1, "..."}

  Levels:

    * stage events log at `:info` on success and `:warning` on failure
    * hook events log at `:debug` on success/skip and `:warning` on failure
  """

  require Logger

  @handler_id "git_hoox.logger"

  @events [
    [:git_hoox, :stage, :stop],
    [:git_hoox, :hook, :stop],
    [:git_hoox, :hook, :skip],
    [:git_hoox, :hook, :exception]
  ]

  @doc "Attach the handler."
  @spec attach() :: :ok | {:error, :already_exists}
  def attach do
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle/4, nil)
  end

  @doc "Detach the handler. Safe to call when not attached."
  @spec detach() :: :ok | {:error, :not_found}
  def detach, do: :telemetry.detach(@handler_id)

  @doc false
  def handle([:git_hoox, :stage, :stop], %{duration: d}, meta, _) do
    %{stage: stage, entries: n, files: f, result: r} = meta
    msg = "[git_hoox] #{stage} → #{r} (#{n} hooks, #{f} files, #{format_duration(d)})"

    case r do
      :ok -> Logger.info(msg)
      _ -> Logger.warning(msg)
    end
  end

  def handle([:git_hoox, :hook, :stop], %{duration: d}, meta, _) do
    %{module: mod, result: r} = meta
    base = "[git_hoox]   #{inspect(mod)} → #{r} (#{format_duration(d)})"

    msg =
      case meta[:error] do
        nil -> base
        reason -> base <> " reason: " <> inspect(reason)
      end

    case r do
      :error -> Logger.warning(msg)
      _ -> Logger.debug(msg)
    end
  end

  def handle([:git_hoox, :hook, :skip], _measurements, meta, _) do
    %{module: mod} = meta
    Logger.debug("[git_hoox]   #{inspect(mod)} → skip (no matched files)")
  end

  def handle([:git_hoox, :hook, :exception], %{duration: d}, meta, _) do
    %{module: mod, kind: kind, reason: reason} = meta

    Logger.error(
      "[git_hoox]   #{inspect(mod)} → exception (#{format_duration(d)}) #{kind}: #{inspect(reason)}"
    )
  end

  defp format_duration(native) do
    ms = System.convert_time_unit(native, :native, :millisecond)

    if ms >= 1_000 do
      "#{Float.round(ms / 1_000, 2)}s"
    else
      "#{ms}ms"
    end
  end
end
