defmodule GitHoox.GitTest do
  use GitHoox.Case, async: false

  alias GitHoox.Git

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  test "staged_files lists --cached only", %{repo: dir} do
    write(dir, "lib/foo.ex", "foo\n")
    write(dir, "lib/bar.ex", "bar\n")
    stage(dir, ["lib/foo.ex"])

    in_repo(dir, fn ->
      assert {:ok, ["lib/foo.ex"]} = Git.staged_files()
    end)
  end

  test "staged_files empty when nothing staged", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, []} = Git.staged_files()
    end)
  end

  test "staged_files handles filenames with spaces", %{repo: dir} do
    write(dir, "lib/has space.ex", "x\n")
    stage(dir, ["lib/has space.ex"])

    in_repo(dir, fn ->
      assert {:ok, ["lib/has space.ex"]} = Git.staged_files()
    end)
  end

  test "staged_files default filter skips deletes", %{repo: dir} do
    write(dir, "lib/keep.ex", "keep\n")
    stage(dir, ["lib/keep.ex"])
    commit(dir, "add keep")
    sh!(dir, ["rm", "lib/keep.ex"])

    in_repo(dir, fn ->
      assert {:ok, []} = Git.staged_files()
      assert {:ok, ["lib/keep.ex"]} = Git.staged_files(filter: "D")
    end)
  end

  test "all_files lists tracked files", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, files} = Git.all_files()
      assert "README.md" in files
    end)
  end

  test "changed_in_worktree detects worktree edits", %{repo: dir} do
    write(dir, "lib/foo.ex", "v1\n")
    stage(dir, ["lib/foo.ex"])
    commit(dir, "add foo")
    write(dir, "lib/foo.ex", "v2\n")

    in_repo(dir, fn ->
      assert ["lib/foo.ex"] = Git.changed_in_worktree(["lib/foo.ex"])
    end)
  end

  test "changed_in_worktree empty for unchanged files", %{repo: dir} do
    write(dir, "lib/foo.ex", "v1\n")
    stage(dir, ["lib/foo.ex"])
    commit(dir, "add foo")

    in_repo(dir, fn ->
      assert [] = Git.changed_in_worktree(["lib/foo.ex"])
    end)
  end

  test "restage adds files to index", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")

    in_repo(dir, fn ->
      assert :ok = Git.restage(["lib/foo.ex"])
      assert {:ok, ["lib/foo.ex"]} = Git.staged_files()
    end)
  end

  test "restage with empty list is no-op", %{repo: dir} do
    in_repo(dir, fn ->
      assert :ok = Git.restage([])
    end)
  end

  test "hooks_dir resolves under .git/hooks", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, path} = Git.hooks_dir()
      assert String.ends_with?(path, "hooks")
    end)
  end

  test "toplevel resolves repo root", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, root} = Git.toplevel()
      expected = dir |> Path.expand() |> Path.basename()
      assert Path.basename(root) == expected
    end)
  end
end
