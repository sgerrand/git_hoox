defmodule GitHoox.RunnerStagesTest do
  use GitHoox.Case, async: false

  alias GitHoox.Runner
  alias GitHoox.TestHooks

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  setup do
    TestHooks.RecordFiles.start_link()
    TestHooks.RecordFiles.reset()
    :ok
  end

  test "commit_msg receives the commit message file path as files", %{repo: dir} do
    write_config(dir, """
    %{hooks: [commit_msg: [{GitHoox.TestHooks.RecordFiles, []}]]}
    """)

    msg_path = Path.join(dir, ".git/COMMIT_EDITMSG")
    File.mkdir_p!(Path.dirname(msg_path))
    File.write!(msg_path, "wip\n")

    in_repo(dir, fn ->
      assert :ok = Runner.run(:commit_msg, [".git/COMMIT_EDITMSG"])
    end)

    assert [".git/COMMIT_EDITMSG"] = TestHooks.RecordFiles.captured()
  end

  test "prepare_commit_msg receives msg file path", %{repo: dir} do
    write_config(dir, """
    %{hooks: [prepare_commit_msg: [{GitHoox.TestHooks.RecordFiles, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:prepare_commit_msg, [".git/COMMIT_EDITMSG", "message"])
    end)

    assert [".git/COMMIT_EDITMSG"] = TestHooks.RecordFiles.captured()
  end

  test "post_commit lists files in HEAD commit", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])
    commit(dir, "add foo")

    write_config(dir, """
    %{hooks: [post_commit: [{GitHoox.TestHooks.RecordFiles, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:post_commit)
    end)

    captured = TestHooks.RecordFiles.captured()
    assert "lib/foo.ex" in captured
  end

  test "post_checkout lists diff between two refs", %{repo: dir} do
    before_sha = sh!(dir, ["rev-parse", "HEAD"]) |> String.trim()
    write(dir, "lib/bar.ex", "x\n")
    stage(dir, ["lib/bar.ex"])
    commit(dir, "add bar")
    after_sha = sh!(dir, ["rev-parse", "HEAD"]) |> String.trim()

    write_config(dir, """
    %{hooks: [post_checkout: [{GitHoox.TestHooks.RecordFiles, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:post_checkout, [before_sha, after_sha, "1"])
    end)

    captured = TestHooks.RecordFiles.captured()
    assert "lib/bar.ex" in captured
  end

  test "post_merge uses ORIG_HEAD..HEAD diff", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])
    commit(dir, "add foo")

    sh!(dir, ["branch", "feature"])
    sh!(dir, ["checkout", "feature"])
    write(dir, "lib/bar.ex", "y\n")
    stage(dir, ["lib/bar.ex"])
    commit(dir, "add bar")
    sh!(dir, ["checkout", "main"])
    sh!(dir, ["merge", "--no-ff", "-m", "merge feature", "feature"])

    write_config(dir, """
    %{hooks: [post_merge: [{GitHoox.TestHooks.RecordFiles, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:post_merge, ["0"])
    end)

    captured = TestHooks.RecordFiles.captured()
    assert "lib/bar.ex" in captured
  end

  test "pre_rebase passes empty file list", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_rebase: [{GitHoox.TestHooks.RecordFiles, files: ["**/*"]}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_rebase, ["main"])
    end)

    assert [] = TestHooks.RecordFiles.captured()
  end

  test "pre_push parses stdin and lists changed files", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])
    commit(dir, "add foo")
    base_sha = sh!(dir, ["rev-parse", "HEAD"]) |> String.trim()

    write(dir, "lib/bar.ex", "y\n")
    stage(dir, ["lib/bar.ex"])
    commit(dir, "add bar")
    head_sha = sh!(dir, ["rev-parse", "HEAD"]) |> String.trim()

    stdin = "refs/heads/main #{head_sha} refs/heads/main #{base_sha}\n"

    write_config(dir, """
    %{hooks: [pre_push: [{GitHoox.TestHooks.RecordFiles, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_push, ["origin", "git@x:y.git"], stdin)
    end)

    captured = TestHooks.RecordFiles.captured()
    assert "lib/bar.ex" in captured
  end
end
