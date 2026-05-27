defmodule GitHoox.Installer do
  @moduledoc """
  Manage `.git/hooks/*` shim files.

  Refuses to overwrite user-authored hooks. Pass `force: true` to back up
  and replace. Detects own shims by `# git_hoox managed` marker.
  """

  alias GitHoox.Git

  @hooks ~w(pre-commit prepare-commit-msg commit-msg post-commit
            pre-rebase post-checkout post-merge pre-push)

  @marker "# git_hoox managed"

  @typedoc "Per-hook installer plan entry."
  @type action ::
          :write
          | :overwrite_managed
          | :overwrite_with_backup

  @type install_error ::
          :not_a_git_repo
          | {:exists, Path.t(), String.t()}

  @type scaffold_error :: {:config_exists, Path.t()}

  @type plan_entry :: {String.t(), Path.t(), action()}

  @config_filename ".git_hoox.exs"

  @doc "Name of the per-repo config file."
  @spec config_filename() :: String.t()
  def config_filename, do: @config_filename

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
  """
  @spec install(keyword()) :: {:ok, [plan_entry()]} | {:error, install_error()}
  def install(opts \\ []) do
    force? = Keyword.get(opts, :force, false)
    dry? = Keyword.get(opts, :dry_run, false)

    with {:ok, dir} <- Git.hooks_dir(),
         :ok <- File.mkdir_p(dir),
         {:ok, plan} <- plan(dir, force?) do
      execute(plan, dry?)
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
    {:ok, root} = Git.toplevel()
    path = Path.join(root, @config_filename)
    force? = Keyword.get(opts, :force, false)

    if File.exists?(path) and not force? do
      {:error, {:config_exists, path}}
    else
      File.write!(path, @default_config)
      {:ok, path}
    end
  end

  @doc "Remove managed shims. Restore latest backup if present."
  @spec uninstall(keyword()) :: {:ok, non_neg_integer()}
  def uninstall(_opts \\ []) do
    case Git.hooks_dir() do
      {:ok, dir} ->
        count =
          @hooks
          |> Enum.map(&Path.join(dir, &1))
          |> Enum.filter(&managed?/1)
          |> Enum.map(&remove_with_restore/1)
          |> Enum.count()

        {:ok, count}

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
    cond do
      not File.exists?(path) ->
        :write

      managed?(path) ->
        :overwrite_managed

      force? ->
        :overwrite_with_backup

      true ->
        {:error,
         {:exists, path,
          "Hook exists and is not managed by git_hoox. Re-run with --force to backup and overwrite."}}
    end
  end

  defp managed?(path) do
    case File.read(path) do
      {:ok, content} -> String.contains?(content, @marker)
      _ -> false
    end
  end

  defp execute(plan, true), do: {:ok, plan}

  defp execute(plan, false) do
    Enum.each(plan, fn {hook, path, action} ->
      if action == :overwrite_with_backup, do: backup(path)
      File.write!(path, shim(hook))
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

  defp latest_backup(path) do
    (path <> ".backup.*")
    |> Path.wildcard()
    |> Enum.sort()
    |> List.last()
  end

  defp shim(hook) do
    """
    #!/usr/bin/env sh
    #{@marker}
    exec mix git_hoox.run #{hook} "$@"
    """
  end
end
