defmodule Mix.Tasks.GitHoox.RunTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.GitHoox.Run, as: RunTask

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  test "no stage argument raises Mix.Error" do
    assert_raise Mix.Error, ~r/Usage/, fn ->
      RunTask.run([])
    end
  end

  test "unknown stage raises Mix.Error and lists valid stages" do
    assert_raise Mix.Error, ~r/Unknown git_hoox stage: bogus/, fn ->
      RunTask.run(["bogus"])
    end
  end

  test "kebab-case stage maps to atom and runs successfully", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = RunTask.run(["pre-commit"])
    end)
  end

  test "failure with generic reason prints `failed:` line and exits 1", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: "plain"]}]]}
    """)

    err =
      capture_io(:stderr, fn ->
        assert {:shutdown, 1} =
                 catch_exit(in_repo(dir, fn -> RunTask.run(["pre-commit"]) end))
      end)

    assert err =~ "Fail failed"
    assert err =~ "plain"
  end

  test "failure with {code, output} prints `failed (exit N)` line", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: {7, "bad"}]}]]}
    """)

    err =
      capture_io(:stderr, fn ->
        catch_exit(in_repo(dir, fn -> RunTask.run(["pre-commit"]) end))
      end)

    assert err =~ "failed (exit 7)"
    assert err =~ "bad"
  end

  test "timeout failure prints `timed out` line", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Slow, timeout: 50, sleep_ms: 500}]]}
    """)

    err =
      capture_io(:stderr, fn ->
        catch_exit(in_repo(dir, fn -> RunTask.run(["pre-commit"]) end))
      end)

    assert err =~ "timed out after 50ms"
  end

  test "crashed hook prints `crashed:` line", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Raiser, [raise_as: :error]}]]}
    """)

    err =
      capture_io(:stderr, fn ->
        catch_exit(in_repo(dir, fn -> RunTask.run(["pre-commit"]) end))
      end)

    assert err =~ "crashed:"
  end

  test "config failure prints catch-all `Hook failure:` line", %{repo: dir} do
    # no .git_hoox.exs → Config.load returns {:error, {:missing_config, _}}.
    # Runner wraps that as {:error, [{:config, reason}]}, which the task's
    # `other` print_failure clause renders.
    err =
      capture_io(:stderr, fn ->
        catch_exit(
          capture_io(fn ->
            in_repo(dir, fn -> RunTask.run(["pre-commit"]) end)
          end)
        )
      end)

    assert err =~ "Hook failure:"
  end

  test "pre-push reads stdin and uses it for file resolution", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_push: []]}
    """)

    # Empty stdin yields :eof → read_stdin returns nil. We still exercise the
    # :pre_push branch of read_stdin/1.
    capture_io("", fn ->
      in_repo(dir, fn ->
        assert :ok = RunTask.run(["pre-push"])
      end)
    end)
  end

  test "pre-push with stdin lines is passed through", %{repo: dir} do
    write_config(dir, """
    %{hooks: [pre_push: []]}
    """)

    # Malformed line is harmless — Git.push_files just yields []. The point is
    # to exercise the binary-data branch of read_stdin/1.
    capture_io("refs/heads/x sha refs/heads/x sha\n", fn ->
      in_repo(dir, fn ->
        assert :ok = RunTask.run(["pre-push"])
      end)
    end)
  end
end
