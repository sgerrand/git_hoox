defmodule Mix.Tasks.GitHoox.BenchTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.GitHoox.Bench, as: BenchTask

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  defp run_task(dir, argv) do
    capture_io(fn -> in_repo(dir, fn -> BenchTask.run(argv) end) end)
  end

  test "runs the configured stage N times and prints a per-module table", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    out = run_task(dir, ["--runs", "3"])

    assert out =~ "Benchmarking pre_commit (3 runs)"
    assert out =~ "GitHoox.TestHooks.Pass"
    assert out =~ "runs"
    assert out =~ "p50"
    assert out =~ "p95"
  end

  test "honours --stage", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_push: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    out = run_task(dir, ["--stage", "pre_push", "--runs", "2"])
    assert out =~ "Benchmarking pre_push (2 runs)"
    assert out =~ "GitHoox.TestHooks.Pass"
  end

  test "kebab-case stage names work", %{repo: dir} do
    write_config(dir, """
    %{hooks: [commit_msg: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    msg = Path.join(dir, ".git/COMMIT_EDITMSG")
    File.mkdir_p!(Path.dirname(msg))
    File.write!(msg, "wip\n")

    out = run_task(dir, ["-s", "commit-msg", "-n", "2"])
    assert out =~ "Benchmarking commit_msg"
  end

  test "no executed hooks reports (no hooks executed)", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_commit: []]}
    """)

    out = run_task(dir, ["--runs", "2"])
    assert out =~ "no hooks executed"
  end

  test "unknown stage raises Mix.Error", %{repo: dir} do
    in_repo(dir, fn ->
      assert_raise Mix.Error, ~r/Unknown git_hoox stage: bogus/, fn ->
        BenchTask.run(["--stage", "bogus"])
      end
    end)
  end

  test "errors column reflects crashed hooks", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Raiser, []}]]}
    """)

    out = run_task(dir, ["--runs", "2"])
    assert out =~ "GitHoox.TestHooks.Raiser"
    assert out =~ "errors"
  end
end
