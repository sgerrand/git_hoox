defmodule GitHoox.Doctor do
  @moduledoc """
  Diagnostic checks for a git_hoox installation.

  Each check reports an `:ok`, `:warn`, or `:error` status with a human
  readable detail string. `run/0` returns the full list; the mix task wrapper
  (`mix git_hoox.doctor`) renders the list and sets the process exit code.
  """

  alias GitHoox.Config
  alias GitHoox.Config.Error, as: ConfigError
  alias GitHoox.Git
  alias GitHoox.Installer

  @typedoc "Single diagnostic outcome."
  @type check :: %{
          name: String.t(),
          status: :ok | :warn | :error,
          detail: String.t()
        }

  @doc "Run every diagnostic in order."
  @spec run() :: [check()]
  def run do
    [
      check_git_repo(),
      check_hooks_dir(),
      check_shims(),
      check_config_present(),
      check_config_valid()
    ]
  end

  @doc "Aggregate severity across checks."
  @spec aggregate([check()]) :: :ok | :warn | :error
  def aggregate(checks) do
    cond do
      Enum.any?(checks, &(&1.status == :error)) -> :error
      Enum.any?(checks, &(&1.status == :warn)) -> :warn
      true -> :ok
    end
  end

  defp check_git_repo do
    case Git.toplevel() do
      {:ok, root} -> ok("git repository", "root: #{root}")
      _ -> error("git repository", "not inside a git working tree")
    end
  end

  defp check_hooks_dir do
    case Git.hooks_dir() do
      {:ok, dir} ->
        if File.dir?(dir),
          do: ok("hooks directory", dir),
          else: warn("hooks directory", "#{dir} does not exist yet")

      _ ->
        error("hooks directory", "could not resolve via git rev-parse")
    end
  end

  defp check_shims do
    case Git.hooks_dir() do
      {:ok, dir} ->
        {managed, foreign, missing, non_exec} = classify_shims(dir)
        summarize_shims(managed, foreign, missing, non_exec)

      _ ->
        error("shims", "hooks directory unavailable")
    end
  end

  defp classify_shims(dir) do
    Enum.reduce(Installer.hook_names(), {[], [], [], []}, fn hook, acc ->
      hook |> shim_kind(dir) |> bucket(hook, acc)
    end)
  end

  defp shim_kind(hook, dir) do
    path = Path.join(dir, hook)

    case File.stat(path) do
      {:error, _} ->
        :missing

      {:ok, %File.Stat{mode: mode}} ->
        cond do
          not Installer.managed?(path) -> :foreign
          Bitwise.band(mode, 0o111) == 0 -> :non_exec
          true -> :managed
        end
    end
  end

  defp bucket(:managed, hook, {m, f, miss, nx}), do: {[hook | m], f, miss, nx}
  defp bucket(:foreign, hook, {m, f, miss, nx}), do: {m, [hook | f], miss, nx}
  defp bucket(:missing, hook, {m, f, miss, nx}), do: {m, f, [hook | miss], nx}
  defp bucket(:non_exec, hook, {m, f, miss, nx}), do: {[hook | m], f, miss, [hook | nx]}

  defp summarize_shims(managed, foreign, missing, non_exec) do
    cond do
      foreign != [] ->
        warn(
          "shims",
          "foreign hooks present: #{Enum.join(foreign, ", ")} (run mix git_hoox.install --force to take over)"
        )

      non_exec != [] ->
        error(
          "shims",
          "managed shims missing executable bit: #{Enum.join(non_exec, ", ")} (chmod +x or re-run mix git_hoox.install)"
        )

      managed == [] ->
        warn("shims", "no git_hoox shims installed (run mix git_hoox.install)")

      missing == [] ->
        ok("shims", "#{length(managed)} managed shims present")

      true ->
        ok("shims", "#{length(managed)} managed shims present (#{length(missing)} unowned)")
    end
  end

  defp check_config_present do
    case config_path() do
      {:ok, path} ->
        if File.exists?(path),
          do: ok("config file", path),
          else:
            warn(
              "config file",
              "#{path} missing (run mix git_hoox.install --scaffold to generate)"
            )

      _ ->
        warn("config file", "could not locate repo root")
    end
  end

  defp check_config_valid do
    case config_path() do
      {:ok, path} -> check_config_at(path)
      _ -> warn("config validates", "skipped — no repo root")
    end
  end

  defp check_config_at(path) do
    if File.exists?(path) do
      load_and_summarize(path)
    else
      warn("config validates", "skipped — no config file")
    end
  end

  defp load_and_summarize(path) do
    case Config.load(path) do
      {:ok, config} ->
        stages = config.hooks |> Keyword.keys() |> Enum.join(", ")
        ok("config validates", "stages: #{stages}")

      {:error, reason} ->
        error("config validates", ConfigError.format(reason))
    end
  end

  defp config_path do
    with {:ok, root} <- Git.toplevel() do
      {:ok, Path.join(root, Installer.config_filename())}
    end
  end

  defp ok(name, detail), do: %{name: name, status: :ok, detail: detail}
  defp warn(name, detail), do: %{name: name, status: :warn, detail: detail}
  defp error(name, detail), do: %{name: name, status: :error, detail: detail}
end
