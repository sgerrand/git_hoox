defmodule GitHoox.GitFixture do
  @moduledoc false

  @spec init_repo(keyword()) :: Path.t()
  def init_repo(opts \\ []) do
    dir = mk_tmp()
    sh!(dir, ["init", "-q", "-b", "main"])
    sh!(dir, ["config", "user.email", "test@git_hoox.local"])
    sh!(dir, ["config", "user.name", "Test"])
    sh!(dir, ["config", "commit.gpgsign", "false"])

    if Keyword.get(opts, :initial_commit, false) do
      write(dir, "README.md", "init\n")
      sh!(dir, ["add", "README.md"])
      sh!(dir, ["commit", "-q", "-m", "init"])
    end

    dir
  end

  @spec write(Path.t(), Path.t(), iodata()) :: :ok
  def write(dir, path, content) do
    full = Path.join(dir, path)
    File.mkdir_p!(Path.dirname(full))
    File.write!(full, content)
  end

  @spec stage(Path.t(), [Path.t()]) :: :ok
  def stage(dir, paths) when is_list(paths) do
    sh!(dir, ["add" | paths])
    :ok
  end

  @spec commit(Path.t(), String.t()) :: :ok
  def commit(dir, msg) do
    sh!(dir, ["commit", "-q", "-m", msg])
    :ok
  end

  @spec staged_files(Path.t()) :: [Path.t()]
  def staged_files(dir) do
    {out, 0} = sh(dir, ["diff", "--cached", "--name-only"])
    String.split(out, "\n", trim: true)
  end

  @doc "Set a git config key in the repo at `dir`."
  @spec set_config(Path.t(), String.t(), String.t()) :: :ok
  def set_config(dir, key, value) do
    sh!(dir, ["config", key, value])
    :ok
  end

  @doc """
  Add a linked worktree at `path` checked out to a new `branch`.

  Returns the worktree path. The caller is responsible for cleanup
  (typically via `on_exit/1`).
  """
  @spec worktree_add(Path.t(), String.t(), Path.t()) :: Path.t()
  def worktree_add(dir, branch, path) do
    sh!(dir, ["worktree", "add", "-q", "-b", branch, path])
    path
  end

  @spec sh(Path.t(), [String.t()]) :: {String.t(), non_neg_integer()}
  def sh(dir, args) do
    System.cmd("git", args, cd: dir, stderr_to_stdout: true, env: clean_env())
  end

  @spec sh!(Path.t(), [String.t()]) :: String.t()
  def sh!(dir, args) do
    case sh(dir, args) do
      {out, 0} -> out
      {out, code} -> raise "git #{Enum.join(args, " ")} failed (#{code}): #{out}"
    end
  end

  # Git exports GIT_DIR, GIT_INDEX_FILE, GIT_PREFIX and friends into any
  # hook it runs. Inheriting those would point every fixture `git` call at
  # the repo being committed/pushed instead of the temp repo, so drop the
  # whole GIT_* namespace (except our own skip vars) before layering the
  # hermetic settings on top. Explicit entries come last so they win over
  # the unsets for keys git also exports (e.g. GIT_AUTHOR_DATE).
  defp clean_env do
    unset_inherited_git_vars() ++
      [
        {"GIT_CONFIG_GLOBAL", "/dev/null"},
        {"GIT_CONFIG_SYSTEM", "/dev/null"},
        {"GIT_AUTHOR_DATE", "2026-01-01T00:00:00Z"},
        {"GIT_COMMITTER_DATE", "2026-01-01T00:00:00Z"}
      ]
  end

  defp unset_inherited_git_vars do
    System.get_env()
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, "GIT_"))
    |> Enum.reject(&String.starts_with?(&1, "GIT_HOOX"))
    |> Enum.map(&{&1, nil})
  end

  defp mk_tmp do
    base = System.tmp_dir!()
    name = "git_hoox_test_#{System.unique_integer([:positive])}"
    dir = Path.join(base, name)
    File.mkdir_p!(dir)
    dir
  end
end
