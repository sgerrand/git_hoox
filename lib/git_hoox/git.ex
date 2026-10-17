defmodule GitHoox.Git do
  @moduledoc """
  Shell out to `git` for file-state queries.

  All functions assume the current working directory is inside a git
  worktree. Errors from the underlying `git` invocation surface as
  `{:error, {exit_code, stdout}}`; git's own stderr is not captured, so it
  reaches the terminal directly and never contaminates parsed output.
  """

  @typedoc "git --diff-filter status letters (e.g. \"ACMR\")."
  @type diff_filter :: String.t()

  @type git_error :: {:error, {non_neg_integer(), String.t()}}

  @doc """
  List files staged for commit.

  ## Options

    * `:filter` — `--diff-filter` letters. Default `"ACMR"` (skip deletes).
  """
  @spec staged_files(keyword()) :: {:ok, [GitHoox.path()]} | git_error()
  def staged_files(opts \\ []) do
    filter = Keyword.get(opts, :filter, "ACMR")

    cmd(["diff", "--cached", "--name-only", "--diff-filter=#{filter}", "-z"])
    |> parse_z()
  end

  @doc "All tracked files via `git ls-files`."
  @spec all_files() :: {:ok, [GitHoox.path()]} | git_error()
  def all_files do
    cmd(["ls-files", "-z"]) |> parse_z()
  end

  @doc """
  Files modified in worktree since index, scoped to `candidates`.
  Used to detect what a hook mutated.
  """
  @spec changed_in_worktree([GitHoox.path()]) :: {:ok, [GitHoox.path()]} | git_error()
  def changed_in_worktree([]), do: {:ok, []}

  def changed_in_worktree(candidates) do
    cmd(["diff", "--name-only", "-z", "--" | candidates]) |> parse_z()
  end

  @doc "Re-stage files via `git add`."
  @spec restage([GitHoox.path()]) :: :ok | git_error()
  def restage([]), do: :ok

  def restage(files) do
    case cmd(["add", "--" | files]) do
      {:ok, _} -> :ok
      err -> err
    end
  end

  @doc "Return absolute path of `.git/hooks/` honoring core.hooksPath + worktrees."
  @spec hooks_dir() :: {:ok, Path.t()} | git_error()
  def hooks_dir, do: trimmed(["rev-parse", "--git-path", "hooks"])

  @doc "Return repo root via `git rev-parse --show-toplevel`."
  @spec toplevel() :: {:ok, Path.t()} | git_error()
  def toplevel, do: trimmed(["rev-parse", "--show-toplevel"])

  @doc "Files touched by the HEAD commit (used for post-commit)."
  @spec files_in_head() :: {:ok, [GitHoox.path()]} | git_error()
  def files_in_head do
    cmd(["show", "--name-only", "--pretty=format:", "-z", "HEAD"])
    |> parse_z()
  end

  @doc "Files changed by the last merge (used for post-merge)."
  @spec merge_files() :: {:ok, [GitHoox.path()]} | git_error()
  def merge_files do
    cmd(["diff-tree", "-r", "--name-only", "--no-commit-id", "-z", "ORIG_HEAD", "HEAD"])
    |> parse_z()
  end

  @doc "Files changed between two refs (used for post-checkout)."
  @spec diff_files(String.t(), String.t()) :: {:ok, [GitHoox.path()]} | git_error()
  def diff_files(from, to) do
    cmd(["diff", "--name-only", "-z", from, to]) |> parse_z()
  end

  @doc """
  Parse pre-push stdin and return files changed across all pushed refs.

  Stdin format per `githooks(5)`:
  `<local_ref> <local_sha> <remote_ref> <remote_sha>` per line.

  For a ref the remote already has, this is the diff across the pushed
  range. Otherwise it is the union of the files touched by every commit
  reachable from the local sha but not from any remote-tracking ref. Git
  does not tell the hook what the remote actually holds, so that
  approximation has two known edges:

    * With no `refs/remotes` at all — a first publish — there is nothing
      to exclude and the whole history's files are listed. Correct in the
      sense that every commit really is being pushed, but it means hooks
      run over the whole tree on that one push.
    * Commits already reachable from some *other* remote-tracking ref are
      excluded, so pushing a new branch to a fork whose base lives on
      `origin` scans less than the full set.

  Both err toward scanning too much rather than too little, which is the
  safer direction for a quality gate.
  """
  @spec push_files(String.t() | nil) :: {:ok, [GitHoox.path()]} | git_error()
  def push_files(nil), do: {:ok, []}
  def push_files(""), do: {:ok, []}

  def push_files(stdin) when is_binary(stdin) do
    stdin
    |> String.split("\n", trim: true)
    |> Enum.reduce_while({:ok, []}, fn line, {:ok, acc} ->
      case push_ref_files(line) do
        {:ok, files} -> {:cont, {:ok, [files | acc]}}
        err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, chunks} -> {:ok, chunks |> Enum.reverse() |> Enum.concat() |> Enum.uniq()}
      err -> err
    end
  end

  defp push_ref_files(line) do
    case String.split(line, " ", trim: true) do
      [_local_ref, local_sha, _remote_ref, remote_sha] ->
        push_kind(local_sha, remote_sha) |> push_files_for(local_sha, remote_sha)

      _ ->
        {:ok, []}
    end
  end

  defp push_kind(local_sha, remote_sha) do
    cond do
      zero_sha?(local_sha) -> :delete
      zero_sha?(remote_sha) -> :create
      true -> :update
    end
  end

  # Deleting a remote ref pushes no content — nothing to scan.
  defp push_files_for(:delete, _local, _remote), do: {:ok, []}

  # `git show` on the tip lists only that one commit's files: a branch with
  # N commits would be scanned as though it were one, and a clean merge tip
  # scans nothing at all, its condensed combined diff being empty. Walk
  # every commit not already reachable from a remote-tracking ref instead
  # and take the union. `-c` keeps merge commits from dropping out, and is
  # used rather than `--diff-merges=combined`, which needs git >= 2.31.
  defp push_files_for(:create, local, _remote) do
    run_split(["log", "-c", "--format=", "--name-only", "-z", local, "--not", "--remotes"])
  end

  # The remote sha comes from the remote's advertised refs, not from our
  # object store, so it is routinely an object we do not hold: a branch
  # that moved upstream since the last fetch, a shallow or partial clone,
  # or a push to an unrelated fork all hand us a sha `git diff` cannot
  # resolve. Scan the tip like a new ref in that case rather than failing
  # the push — git's own non-fast-forward error is the one the user needs
  # to see, and aborting here would hide it.
  defp push_files_for(:update, local, remote) do
    if have_object?(remote) do
      run_split(["diff", "--name-only", "-z", "#{remote}..#{local}"])
    else
      push_files_for(:create, local, remote)
    end
  end

  defp have_object?(sha), do: match?({:ok, _}, cmd(["cat-file", "-e", sha]))

  defp run_split(args), do: args |> cmd() |> parse_z()

  defp zero_sha?(sha), do: sha != "" and String.replace(sha, "0", "") == ""

  # stderr is left on the inherited stream rather than merged into the
  # captured output: this output is parsed (file lists, paths), and a git
  # warning such as a CRLF notice would otherwise be read as a filename.
  defp cmd(args) do
    case System.cmd("git", args) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {code, out}}
    end
  end

  defp trimmed(args) do
    with {:ok, out} <- cmd(args), do: {:ok, String.trim(out)}
  end

  defp parse_z({:ok, out}), do: {:ok, split_z(out)}
  defp parse_z(err), do: err

  defp split_z(out), do: String.split(out, <<0>>, trim: true)
end
