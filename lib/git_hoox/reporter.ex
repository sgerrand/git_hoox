defmodule GitHoox.Reporter do
  @moduledoc """
  Reference `:telemetry` handler that prints coloured hook status to the
  terminal.

  Sibling of `GitHoox.Logger`: same events, but writes plain `IO` lines
  (no log levels, no timestamps, no `Logger` config) so the output reads
  as a status report rather than a log. Attach it before running hooks:

      GitHoox.Reporter.attach()

  `mix git_hoox.run` attaches it by default; set `config :git_hoox,
  reporter: false` to opt out. Detach with `GitHoox.Reporter.detach/0`.

  Output looks like:

      → pre-commit · 3 hooks · 5 files
        ▸ Format
        ✓ Format · 38ms
        ▸ Credo
        ✗ Credo · exit 1 · 1.4s
        - Test · skipped (no matched files)
      ✗ pre-commit · 1/3 failed · 1.5s

  Stages with no configured hooks print nothing (every commit fires
  several shims; without this they would all emit noise).

  ## Colour

  Colour is decided once at `attach/0` and fixed for the handler's life.
  Precedence, first match wins:

    1. `GIT_HOOX_COLOR=always` → on, `=never` → off.
    2. `NO_COLOR` set (any value) → off.
    3. `CLICOLOR_FORCE` / `FORCE_COLOR` set and not `"0"` → on.
    4. `IO.ANSI.enabled?/0` — true on a TTY, false through a pipe.

  Pass `attach(color: true)` / `attach(color: false)` to override the
  detection (used by tests).
  """

  @handler_id "git_hoox.reporter"

  @events [
    [:git_hoox, :stage, :start],
    [:git_hoox, :stage, :stop],
    [:git_hoox, :stage, :exception],
    [:git_hoox, :hook, :start],
    [:git_hoox, :hook, :stop],
    [:git_hoox, :hook, :skip],
    [:git_hoox, :hook, :exception]
  ]

  @doc """
  Attach the handler.

  Options:

    * `:color` — force colour on/off, skipping environment detection.
  """
  @spec attach(keyword()) :: :ok | {:error, :already_exists}
  def attach(opts \\ []) do
    color? = Keyword.get_lazy(opts, :color, &color_enabled?/0)
    :telemetry.attach_many(@handler_id, @events, &__MODULE__.handle/4, %{color?: color?})
  end

  @doc "Detach the handler. Safe to call when not attached."
  @spec detach() :: :ok | {:error, :not_found}
  def detach, do: :telemetry.detach(@handler_id)

  @doc false
  def handle([:git_hoox, :stage, :start], _measurements, %{entries: 0}, _config), do: :ok

  def handle([:git_hoox, :stage, :start], _measurements, meta, config) do
    %{stage: stage, entries: e, files: f} = meta

    emit(config, [
      :cyan,
      "→ ",
      :reset,
      :bright,
      stage_name(stage),
      :reset,
      :light_black,
      " · #{count(e, "hook")} · #{count(f, "file")}"
    ])
  end

  def handle([:git_hoox, :stage, :stop], _measurements, %{entries: 0}, _config), do: :ok

  def handle([:git_hoox, :stage, :stop], %{duration: d}, %{result: :ok} = meta, config) do
    %{stage: stage, entries: e} = meta

    emit(config, [
      :green,
      "✓ ",
      :reset,
      stage_name(stage),
      :light_black,
      " · #{count(e, "hook")} · #{format_duration(d)}"
    ])
  end

  def handle([:git_hoox, :stage, :stop], %{duration: d}, %{result: :error} = meta, config) do
    %{stage: stage, entries: e, failures: fl} = meta

    emit(config, [
      :red,
      "✗ ",
      :reset,
      stage_name(stage),
      :light_black,
      " · ",
      :reset,
      :red,
      "#{fl}/#{e} failed",
      :reset,
      :light_black,
      " · #{format_duration(d)}"
    ])
  end

  def handle([:git_hoox, :stage, :exception], _measurements, meta, config) do
    emit(config, [:red, "✗ ", stage_name(meta.stage), " · crashed", :reset])
  end

  def handle([:git_hoox, :hook, :start], _measurements, meta, config) do
    emit(config, [:light_black, "  ▸ #{hook_name(meta.module)}"])
  end

  def handle([:git_hoox, :hook, :stop], %{duration: d}, %{result: :ok} = meta, config) do
    emit(config, [
      :green,
      "  ✓ ",
      :reset,
      hook_name(meta.module),
      :light_black,
      " · #{format_duration(d)}"
    ])
  end

  def handle([:git_hoox, :hook, :stop], _measurements, %{result: :skip} = meta, config) do
    emit(config, [:light_black, "  - #{hook_name(meta.module)} · skipped (no matched files)"])
  end

  def handle([:git_hoox, :hook, :stop], %{duration: d}, %{result: :error} = meta, config) do
    emit(config, [
      :red,
      "  ✗ ",
      :reset,
      hook_name(meta.module),
      :light_black,
      " · ",
      :reset,
      :red,
      reason_label(meta.error),
      :reset,
      :light_black,
      " · #{format_duration(d)}"
    ])
  end

  def handle([:git_hoox, :hook, :skip], _measurements, meta, config) do
    emit(config, [:light_black, "  - #{hook_name(meta.module)} · skipped (no matched files)"])
  end

  def handle(
        [:git_hoox, :hook, :exception],
        _measurements,
        %{reason: {:git_hoox_timeout, ms}} = meta,
        config
      ) do
    emit(config, [
      :red,
      "  ✗ ",
      :reset,
      hook_name(meta.module),
      :light_black,
      " · ",
      :reset,
      :red,
      "timeout after #{ms}ms",
      :reset
    ])
  end

  def handle([:git_hoox, :hook, :exception], _measurements, meta, config) do
    %{module: mod, kind: kind, reason: reason} = meta

    emit(config, [
      :red,
      "  ✗ ",
      :reset,
      hook_name(mod),
      :light_black,
      " · ",
      :reset,
      :red,
      "crashed · #{kind}: #{truncate(inspect(reason))}",
      :reset
    ])
  end

  # Mandatory: :telemetry silently detaches a handler that raises, so an
  # event shape we did not anticipate must never blow up the handler.
  def handle(_event, _measurements, _meta, _config), do: :ok

  defp emit(%{color?: color?}, ansidata) do
    IO.puts(IO.ANSI.format(ansidata, color?))
  end

  defp reason_label({code, out}) when is_integer(code) and is_binary(out), do: "exit #{code}"
  defp reason_label(other), do: truncate(inspect(other))

  defp stage_name(stage), do: stage |> Atom.to_string() |> String.replace("_", "-")

  defp hook_name(mod), do: mod |> inspect() |> String.replace_prefix("GitHoox.Hooks.", "")

  defp count(n, word), do: "#{n} #{word}#{if n == 1, do: "", else: "s"}"

  defp truncate(str, max \\ 120) do
    if String.length(str) > max, do: String.slice(str, 0, max) <> "…", else: str
  end

  defp format_duration(native) do
    ms = System.convert_time_unit(native, :native, :millisecond)

    if ms >= 1_000 do
      "#{Float.round(ms / 1_000, 2)}s"
    else
      "#{ms}ms"
    end
  end

  defp color_enabled? do
    case System.get_env("GIT_HOOX_COLOR") do
      "always" -> true
      "never" -> false
      _ -> color_from_env()
    end
  end

  defp color_from_env do
    cond do
      System.get_env("NO_COLOR") != nil -> false
      forced?(System.get_env("CLICOLOR_FORCE")) -> true
      forced?(System.get_env("FORCE_COLOR")) -> true
      true -> IO.ANSI.enabled?()
    end
  end

  defp forced?(nil), do: false
  defp forced?(""), do: false
  defp forced?("0"), do: false
  defp forced?(_), do: true
end
