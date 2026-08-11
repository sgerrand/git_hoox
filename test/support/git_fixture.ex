defmodule GitHoox.GitFixture do
  @moduledoc false

  # Test identity, passed per-invocation via `git -c` rather than written
  # with `git config`. A config write lands wherever the command resolves
  # its repo, so if a GIT_DIR ever leaks in again the write would persist
  # these credentials in a real repository's config and silently author
  # that user's commits as "Test". `-c` cannot outlive the process.
  @identity [
    {"user.email", "test@git_hoox.local"},
    {"user.name", "Test"},
    {"commit.gpgsign", "false"}
  ]

  @spec init_repo(keyword()) :: Path.t()
  def init_repo(opts \\ []) do
    dir = mk_tmp()
    sh!(dir, ["init", "-q", "-b", "main"])

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
    refute_inherited_git_dir!()
    System.cmd("git", identity_flags() ++ args, cd: dir, stderr_to_stdout: true, env: clean_env())
  end

  defp identity_flags do
    Enum.flat_map(@identity, fn {key, value} -> ["-c", "#{key}=#{value}"] end)
  end

  # `cd:` does not win against GIT_DIR — git would target the leaked repo
  # instead of `dir`, writing fixture commits into it. test_helper.exs
  # clears these before ExUnit starts; fail loudly rather than corrupt a
  # real repository if that ever stops working.
  defp refute_inherited_git_dir! do
    case Enum.filter(~w(GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE), &System.get_env/1) do
      [] ->
        :ok

      leaked ->
        raise "inherited #{Enum.join(leaked, ", ")} would retarget fixture git calls " <>
                "at a real repository — test_helper.exs should have cleared these"
    end
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

  # System.unique_integer/1 restarts at 1 in every VM, so a bare counter
  # collides with repos left behind by earlier runs: `git init` re-inits
  # the stale repo, its "init" commit is already there, and the fixture
  # dies with "nothing to commit, working tree clean". Scope the name to
  # this OS process and clear any directory that somehow survives.
  defp mk_tmp do
    base = System.tmp_dir!()
    name = "git_hoox_test_#{System.pid()}_#{System.unique_integer([:positive])}"
    dir = Path.join(base, name)
    File.rm_rf!(dir)
    File.mkdir_p!(dir)
    dir
  end
end
