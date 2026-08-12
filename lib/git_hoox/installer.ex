defmodule GitHoox.Installer do
  @moduledoc """
  Manage `.git/hooks/*` shim files.

  Refuses to overwrite user-authored hooks. Pass `force: true` to back up
  and replace. Detects own shims by `# git_hoox managed` marker.
  """

  alias GitHoox.Config
  alias GitHoox.Config.Schema
  alias GitHoox.Git

  # Derived from Schema.valid_stages/0 so adding a stage writes a shim
  # without a second list to keep in sync.
  @hooks Schema.hook_filenames()

  @marker "# git_hoox managed"

  @typedoc "Per-hook installer plan entry."
  @type action ::
          :write
          | :overwrite_managed
          | :overwrite_with_backup

  @type install_error ::
          :not_a_git_repo
          | {:exists, Path.t(), String.t()}

  @type scaffold_error ::
          {:config_exists, Path.t()}
          | {non_neg_integer(), String.t()}

  @type plan_entry :: {String.t(), Path.t(), action()}

  @doc "Name of the per-repo config file."
  @spec config_filename() :: String.t()
  def config_filename, do: Config.default_path()

  @doc "Kebab-case names of every git stage git_hoox manages."
  @spec hook_names() :: [String.t()]
  def hook_names, do: @hooks

  @doc "True if the file at `path` is a git_hoox-managed shim."
  @spec managed?(Path.t()) :: boolean()
  def managed?(path) do
    case File.read(path) do
      {:ok, content} -> String.contains?(content, @marker)
      _ -> false
    end
  end

  @default_config """
  %{
    hooks: [
      pre_commit: [
        {GitHoox.Hooks.Format, []},
        {GitHoox.Hooks.Credo, []}
      ],
      pre_push: [
        {GitHoox.Hooks.Test, scope: :stale}
      ]
    ]
  }
  """

  @doc """
  Install hook shims into `.git/hooks/`.

  ## Options

    * `:force` — overwrite user hooks with backup. Default `false`.
    * `:dry_run` — print plan, no writes. Default `false`.
    * `:auto_deps_get` — prepend a `mix deps.get` self-heal line to each
      shim. Default `false`.
  """
  @spec install(keyword()) :: {:ok, [plan_entry()]} | {:error, install_error()}
  def install(opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    dry? = Keyword.get(opts, :dry_run, false)
    auto? = Keyword.get(opts, :auto_deps_get, false)

    with {:ok, dir} <- Git.hooks_dir(),
         :ok <- File.mkdir_p(dir),
         {:ok, plan} <- plan(dir, force?) do
      execute(plan, dry?, auto?)
    end
  end

  @doc """
  Write a starter `.git_hoox.exs` at the repo root.

  ## Options

    * `:force` — overwrite existing config. Default `false`.

  Returns `{:ok, path}` on success or `{:error, {:config_exists, path}}`
  if the file already exists and `:force` is false.
  """
  @spec scaffold(keyword()) :: {:ok, Path.t()} | {:error, scaffold_error()}
  def scaffold(opts \\ []) do
    with {:ok, root} <- Git.toplevel() do
      path = Path.join(root, config_filename())
      force? = Keyword.get(opts, :force, false)

      if File.exists?(path) and not force? do
        {:error, {:config_exists, path}}
      else
        File.write!(path, @default_config)
        {:ok, path}
      end
    end
  end

  @doc "Remove managed shims. Restore latest backup if present."
  @spec uninstall(keyword()) :: {:ok, non_neg_integer()}
  def uninstall(_opts \\ []) do
    case Git.hooks_dir() do
      {:ok, dir} ->
        paths =
          @hooks
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&managed?/1)

        Enum.each(paths, &remove_with_restore/1)

        {:ok, length(paths)}

      {:error, _} ->
        {:ok, 0}
    end
  end

  defp plan(dir, force?) do
    Enum.reduce_while(@hooks, {:ok, []}, fn hook, {:ok, acc} ->
      path = Path.join(dir, hook)

      case classify(path, force?) do
        {:error, _} = err -> {:halt, err}
        action -> {:cont, {:ok, [{hook, path, action} | acc]}}
      end
    end)
    |> case do
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      err -> err
    end
  end

  defp classify(path, force?) do
    case File.read(path) do
      {:error, :enoent} ->
        :write

      # Something is there but cannot be inspected — a directory, or a file
      # this user cannot read. Treat it exactly like a foreign hook rather
      # than an empty slot, and report the underlying IO error.
      {:error, reason} ->
        occupied(path, force?, "Hook exists but could not be read (#{error_text(reason)}).")

      {:ok, content} ->
        if String.contains?(content, @marker) do
          :overwrite_managed
        else
          occupied(path, force?, "Hook exists and is not managed by git_hoox.")
        end
    end
  end

  defp occupied(_path, true, _detail), do: :overwrite_with_backup

  defp occupied(path, false, detail) do
    {:error, {:exists, path, detail <> " Re-run with --force to backup and overwrite."}}
  end

  defp error_text(reason), do: reason |> :file.format_error() |> List.to_string()

  defp execute(plan, true, _auto?), do: {:ok, plan}

  defp execute(plan, false, auto?) do
    Enum.each(plan, fn {hook, path, action} ->
      if action == :overwrite_with_backup, do: backup(path)
      File.write!(path, shim(hook, auto?))
      File.chmod!(path, 0o755)
    end)

    {:ok, plan}
  end

  defp backup(path) do
    ts =
      DateTime.utc_now()
      |> DateTime.truncate(:second)
      |> DateTime.to_iso8601(:basic)

    File.rename!(path, "#{path}.backup.#{ts}")
  end

  defp remove_with_restore(path) do
    File.rm!(path)

    case latest_backup(path) do
      nil -> :ok
      backup -> File.rename!(backup, path)
    end
  end

  # Match the basic-format ISO8601 timestamp written by backup/1 so a
  # stray sibling like `pre-commit.backup.swp` does not outsort a real
  # backup and get restored on uninstall.
  @backup_suffix ~r/\.backup\.\d{8}T\d{6}Z$/

  defp latest_backup(path) do
    (path <> ".backup.*")
    |> Path.wildcard()
    |> Enum.filter(&Regex.match?(@backup_suffix, &1))
    |> Enum.sort()
    |> List.last()
  end

  @deps_get_line "mix deps.get --check-locked >/dev/null 2>&1 || mix deps.get\n"

  defp shim(hook, auto?) do
    """
    #!/usr/bin/env sh
    #{@marker}
    #{if auto?, do: @deps_get_line, else: ""}exec mix git_hoox.run #{hook} "$@"
    """
  end
end
