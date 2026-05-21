defmodule GitHoox.RunnerTest do
  use GitHoox.Case, async: false

  alias GitHoox.Runner
  alias GitHoox.TestHooks

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  setup do
    TestHooks.Counter.start_link()
    TestHooks.Counter.reset()
    :ok
  end

  test "no hooks for stage returns :ok", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_commit: []]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)
  end

  test "single passing hook returns :ok", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)
  end

  test "failing hook returns {:error, failures}", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: "nope"]}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, [{GitHoox.TestHooks.Fail, {:error, "nope"}}]} = Runner.run(:pre_commit)
    end)
  end

  test "no staged files = hook skipped", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Counter, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)

    assert TestHooks.Counter.count() == 0
  end

  test "fail_fast halts after first failure", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{
      hooks: [pre_commit: [
        {GitHoox.TestHooks.Fail, []},
        {GitHoox.TestHooks.Counter, []}
      ]],
      fail_fast: true
    }
    """)

    in_repo(dir, fn ->
      assert {:error, failures} = Runner.run(:pre_commit)
      assert length(failures) == 1
    end)

    assert TestHooks.Counter.count() == 0
  end

  test "non-fail-fast runs all hooks despite failure", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [
      {GitHoox.TestHooks.Fail, []},
      {GitHoox.TestHooks.Counter, []}
    ]]}
    """)

    in_repo(dir, fn ->
      assert {:error, _} = Runner.run(:pre_commit)
    end)

    assert TestHooks.Counter.count() == 1
  end

  test "stage_fixed: true re-stages mutated files", %{repo: dir} do
    write(dir, "lib/foo.ex", "v1\n")
    stage(dir, ["lib/foo.ex"])
    commit(dir, "add foo")

    write(dir, "lib/foo.ex", "v2\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.MutateAndReport, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)

    {staged_diff, 0} = sh(dir, ["diff", "--cached", "lib/foo.ex"])
    assert staged_diff =~ "mutated"
  end

  test "skip env=0 disables all hooks", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Counter, []}]]}
    """)

    System.put_env("GIT_HOOX", "0")

    try do
      in_repo(dir, fn ->
        assert :ok = Runner.run(:pre_commit)
      end)

      assert TestHooks.Counter.count() == 0
    after
      System.delete_env("GIT_HOOX")
    end
  end

  test "skip env exclude filters specific hooks", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [
      {GitHoox.TestHooks.Counter, []},
      {GitHoox.TestHooks.Fail, []}
    ]]}
    """)

    System.put_env("GIT_HOOX_EXCLUDE", "fail")

    try do
      in_repo(dir, fn ->
        assert :ok = Runner.run(:pre_commit)
      end)

      assert TestHooks.Counter.count() == 1
    after
      System.delete_env("GIT_HOOX_EXCLUDE")
    end
  end

  test "skip env only filters to a single hook", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [
      {GitHoox.TestHooks.Counter, []},
      {GitHoox.TestHooks.Fail, []}
    ]]}
    """)

    System.put_env("GIT_HOOX_ONLY", "counter")

    try do
      in_repo(dir, fn ->
        assert :ok = Runner.run(:pre_commit)
      end)

      assert TestHooks.Counter.count() == 1
    after
      System.delete_env("GIT_HOOX_ONLY")
    end
  end

  test "glob filter matches lib/**/*.ex", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    write(dir, "lib/nested/bar.ex", "x\n")
    write(dir, "README.md", "x\n")
    stage(dir, ["lib/foo.ex", "lib/nested/bar.ex", "README.md"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Counter, files: ["lib/**/*.ex"]}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)

    assert TestHooks.Counter.count() == 1
  end

  test "parallel execution runs all hooks", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{
      hooks: [pre_commit: [
        {GitHoox.TestHooks.Counter, []},
        {GitHoox.TestHooks.Counter, []},
        {GitHoox.TestHooks.Counter, []}
      ]],
      parallel: true
    }
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)

    assert TestHooks.Counter.count() == 3
  end
end
