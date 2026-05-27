defmodule GitHoox.Git do
  @moduledoc """
  Shell out to `git` for file-state queries.

  All functions assume the current working directory is inside a git
  worktree. Errors from the underlying `git` invocation surface as
  `{:error, {exit_code, stderr}}`.
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
  @spec changed_in_worktree([GitHoox.path()]) :: [GitHoox.path()]
  def changed_in_worktree([]), do: []

  def changed_in_worktree(candidates) do
    case cmd(["diff", "--name-only", "-z", "--" | candidates]) do
      {:ok, out} -> split_z(out)
      _ -> []
    end
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
  def hooks_dir do
    case cmd(["rev-parse", "--git-path", "hooks"]) do
      {:ok, out} -> {:ok, String.trim(out)}
      err -> err
    end
  end

  @doc "Return repo root via `git rev-parse --show-toplevel`."
  @spec toplevel() :: {:ok, Path.t()} | git_error()
  def toplevel do
    case cmd(["rev-parse", "--show-toplevel"]) do
      {:ok, out} -> {:ok, String.trim(out)}
      err -> err
    end
  end

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
  """
  @spec push_files(String.t() | nil) :: {:ok, [GitHoox.path()]}
  def push_files(nil), do: {:ok, []}
  def push_files(""), do: {:ok, []}

  def push_files(stdin) when is_binary(stdin) do
    files =
      stdin
      |> String.split("\n", trim: true)
      |> Enum.flat_map(&push_ref_files/1)
      |> Enum.uniq()

    {:ok, files}
  end

  defp push_ref_files(line) do
    case String.split(line, " ", trim: true) do
      [_local_ref, local_sha, _remote_ref, remote_sha] ->
        push_kind(local_sha, remote_sha) |> push_files_for(local_sha, remote_sha)

      _ ->
        []
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
  defp push_files_for(:delete, _local, _remote), do: []

  defp push_files_for(:create, local, _remote) do
    run_split(["show", "--name-only", "--pretty=format:", "-z", local])
  end

  defp push_files_for(:update, local, remote) do
    run_split(["diff", "--name-only", "-z", "#{remote}..#{local}"])
  end

  defp run_split(args) do
    case cmd(args) do
      {:ok, out} -> split_z(out)
      _ -> []
    end
  end

  defp zero_sha?(sha), do: sha != "" and String.replace(sha, "0", "") == ""

  defp cmd(args) do
    case System.cmd("git", args, stderr_to_stdout: true) do
      {out, 0} -> {:ok, out}
      {out, code} -> {:error, {code, out}}
    end
  end

  defp parse_z({:ok, out}), do: {:ok, split_z(out)}
  defp parse_z(err), do: err

  defp split_z(out), do: String.split(out, <<0>>, trim: true)
end
