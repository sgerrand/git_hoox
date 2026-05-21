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

  defp clean_env do
    [
      {"GIT_CONFIG_GLOBAL", "/dev/null"},
      {"GIT_CONFIG_SYSTEM", "/dev/null"},
      {"GIT_AUTHOR_DATE", "2026-01-01T00:00:00Z"},
      {"GIT_COMMITTER_DATE", "2026-01-01T00:00:00Z"}
    ]
  end

  defp mk_tmp do
    base = System.tmp_dir!()
    name = "git_hoox_test_#{System.unique_integer([:positive])}"
    dir = Path.join(base, name)
    File.mkdir_p!(dir)
    dir
  end
end
