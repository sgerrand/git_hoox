defmodule GitHoox.GitStagesTest do
  use GitHoox.Case, async: false

  alias GitHoox.Git

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  describe "files_in_head/0" do
    test "lists files touched by HEAD", %{repo: dir} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])
      commit(dir, "add foo")

      in_repo(dir, fn ->
        assert {:ok, files} = Git.files_in_head()
        assert "lib/foo.ex" in files
      end)
    end
  end

  describe "merge_files/0" do
    test "lists files merged between ORIG_HEAD and HEAD", %{repo: dir} do
      # Create branch + diverge + merge.
      sh!(dir, ["checkout", "-q", "-b", "feature"])
      write(dir, "lib/feature.ex", "f\n")
      stage(dir, ["lib/feature.ex"])
      commit(dir, "feature")
      sh!(dir, ["checkout", "-q", "main"])
      sh!(dir, ["merge", "-q", "--no-ff", "-m", "merge", "feature"])

      in_repo(dir, fn ->
        assert {:ok, files} = Git.merge_files()
        assert "lib/feature.ex" in files
      end)
    end
  end

  describe "diff_files/2" do
    test "diff between two refs lists changed paths", %{repo: dir} do
      write(dir, "lib/a.ex", "a\n")
      stage(dir, ["lib/a.ex"])
      commit(dir, "a")
      first = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      write(dir, "lib/b.ex", "b\n")
      stage(dir, ["lib/b.ex"])
      commit(dir, "b")
      second = String.trim(sh!(dir, ["rev-parse", "HEAD"]))

      in_repo(dir, fn ->
        assert {:ok, files} = Git.diff_files(first, second)
        assert "lib/b.ex" in files
      end)
    end
  end

  describe "push_files/1" do
    test "nil and empty string short-circuit to []" do
      assert {:ok, []} = Git.push_files(nil)
      assert {:ok, []} = Git.push_files("")
    end

    test "malformed line yields empty list" do
      assert {:ok, []} = Git.push_files("garbage line\n")
    end

    test "well-formed line with both shas runs diff branch", %{repo: dir} do
      write(dir, "lib/a.ex", "a\n")
      stage(dir, ["lib/a.ex"])
      commit(dir, "a")
      first = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      write(dir, "lib/b.ex", "b\n")
      stage(dir, ["lib/b.ex"])
      commit(dir, "b")
      second = String.trim(sh!(dir, ["rev-parse", "HEAD"]))

      line = "refs/heads/main #{second} refs/heads/main #{first}\n"

      in_repo(dir, fn ->
        assert {:ok, files} = Git.push_files(line)
        assert "lib/b.ex" in files
      end)
    end

    test "all-zero remote sha takes the show-new-branch branch", %{repo: dir} do
      write(dir, "lib/x.ex", "x\n")
      stage(dir, ["lib/x.ex"])
      commit(dir, "x")
      sha = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      zero = String.duplicate("0", String.length(sha))
      line = "refs/heads/main #{sha} refs/heads/main #{zero}\n"

      in_repo(dir, fn ->
        assert {:ok, files} = Git.push_files(line)
        assert "lib/x.ex" in files
      end)
    end

    test "git error on bogus sha yields empty list", %{repo: dir} do
      line =
        "refs/heads/main deadbeefdeadbeefdeadbeefdeadbeefdeadbeef " <>
          "refs/heads/main cafebabecafebabecafebabecafebabecafebabe\n"

      in_repo(dir, fn ->
        assert {:ok, []} = Git.push_files(line)
      end)
    end
  end

  describe "changed_in_worktree/1" do
    test "empty list short-circuits" do
      assert [] = Git.changed_in_worktree([])
    end

    test "non-existent file yields empty list", %{repo: dir} do
      in_repo(dir, fn ->
        assert [] = Git.changed_in_worktree(["does/not/exist.ex"])
      end)
    end
  end

  describe "restage/1" do
    test "git error surfaces", %{repo: _dir} do
      # Run outside a git repo: git add will fail.
      tmp = Path.join(System.tmp_dir!(), "no_repo_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)

      File.cd!(tmp, fn ->
        assert {:error, {_code, _msg}} = Git.restage(["whatever.ex"])
      end)
    end
  end
end
