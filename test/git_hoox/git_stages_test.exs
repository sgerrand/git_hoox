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

    test "all-zero remote sha takes the new-branch branch", %{repo: dir} do
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

    test "all-zero local sha (branch delete) yields empty list without running git", %{
      repo: dir
    } do
      zero = String.duplicate("0", 40)
      bogus_remote = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
      line = "refs/heads/main #{zero} refs/heads/main #{bogus_remote}\n"

      in_repo(dir, fn ->
        assert {:ok, []} = Git.push_files(line)
      end)
    end

    test "git error on bogus sha surfaces instead of yielding no files", %{repo: dir} do
      line =
        "refs/heads/main deadbeefdeadbeefdeadbeefdeadbeefdeadbeef " <>
          "refs/heads/main cafebabecafebabecafebabecafebabecafebabe\n"

      in_repo(dir, fn ->
        assert {:error, {code, _out}} = Git.push_files(line)
        assert is_integer(code) and code != 0
      end)
    end

    test "remote sha absent from the object store falls back to the tip listing", %{repo: dir} do
      write(dir, "lib/a.ex", "a\n")
      stage(dir, ["lib/a.ex"])
      commit(dir, "a")
      local = String.trim(sh!(dir, ["rev-parse", "HEAD"]))

      # Shaped like a real sha, but no such object here: what git hands
      # the hook whenever the remote branch moved on since our last fetch.
      unfetched = String.duplicate("b", 40)
      line = "refs/heads/main #{local} refs/heads/main #{unfetched}\n"

      in_repo(dir, fn ->
        assert {:ok, files} = Git.push_files(line)
        assert "lib/a.ex" in files
      end)
    end

    test "a new branch lists files from every pushed commit, not just the tip", %{repo: dir} do
      for name <- ~w(one two three) do
        write(dir, "lib/#{name}.ex", "x\n")
        stage(dir, ["lib/#{name}.ex"])
        commit(dir, "add #{name}")
      end

      sha = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      zero = String.duplicate("0", String.length(sha))
      line = "refs/heads/main #{sha} refs/heads/main #{zero}\n"

      in_repo(dir, fn ->
        assert {:ok, files} = Git.push_files(line)
        assert "lib/one.ex" in files
        assert "lib/two.ex" in files
        assert "lib/three.ex" in files
      end)
    end

    test "a merge tip lists the files merged in, not an empty set", %{repo: dir} do
      sh!(dir, ["checkout", "-q", "-b", "feature"])
      write(dir, "lib/feature.ex", "f\n")
      stage(dir, ["lib/feature.ex"])
      commit(dir, "feature")
      sh!(dir, ["checkout", "-q", "main"])
      write(dir, "lib/mainline.ex", "m\n")
      stage(dir, ["lib/mainline.ex"])
      commit(dir, "mainline")
      sh!(dir, ["merge", "-q", "--no-ff", "-m", "merge feature", "feature"])

      sha = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      zero = String.duplicate("0", String.length(sha))
      line = "refs/heads/main #{sha} refs/heads/main #{zero}\n"

      # A clean merge's condensed combined diff is empty, so listing the
      # tip alone would leave the entire side branch unscanned.
      in_repo(dir, fn ->
        assert {:ok, files} = Git.push_files(line)
        assert "lib/feature.ex" in files
        assert "lib/mainline.ex" in files
      end)
    end

    test "commits already on a remote-tracking ref are excluded", %{repo: dir} do
      write(dir, "lib/pushed.ex", "p\n")
      stage(dir, ["lib/pushed.ex"])
      commit(dir, "already pushed")
      sh!(dir, ["update-ref", "refs/remotes/origin/main", "HEAD"])

      write(dir, "lib/fresh.ex", "n\n")
      stage(dir, ["lib/fresh.ex"])
      commit(dir, "not yet pushed")

      sha = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      zero = String.duplicate("0", String.length(sha))
      line = "refs/heads/main #{sha} refs/heads/main #{zero}\n"

      in_repo(dir, fn ->
        assert {:ok, files} = Git.push_files(line)
        assert "lib/fresh.ex" in files
        refute "lib/pushed.ex" in files
      end)
    end

    test "a failing ref aborts the whole parse", %{repo: dir} do
      write(dir, "lib/a.ex", "a\n")
      stage(dir, ["lib/a.ex"])
      commit(dir, "a")
      sha = String.trim(sh!(dir, ["rev-parse", "HEAD"]))
      zero = String.duplicate("0", String.length(sha))

      good = "refs/heads/main #{sha} refs/heads/main #{zero}\n"
      bad = "refs/heads/x #{String.duplicate("a", 40)} refs/heads/x #{String.duplicate("b", 40)}\n"

      in_repo(dir, fn ->
        assert {:error, {_code, _out}} = Git.push_files(good <> bad)
      end)
    end
  end

  describe "changed_in_worktree/1" do
    test "empty list short-circuits" do
      assert {:ok, []} = Git.changed_in_worktree([])
    end

    test "non-existent file yields empty list", %{repo: dir} do
      in_repo(dir, fn ->
        assert {:ok, []} = Git.changed_in_worktree(["does/not/exist.ex"])
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
