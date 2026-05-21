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
        zero = String.duplicate("0", String.length(local_sha))

        args =
          if remote_sha == zero do
            ["show", "--name-only", "--pretty=format:", "-z", local_sha]
          else
            ["diff", "--name-only", "-z", "#{remote_sha}..#{local_sha}"]
          end

        case cmd(args) do
          {:ok, out} -> split_z(out)
          _ -> []
        end

      _ ->
        []
    end
  end

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
