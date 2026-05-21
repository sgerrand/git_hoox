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
