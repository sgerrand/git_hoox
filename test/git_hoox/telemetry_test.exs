defmodule GitHoox.TelemetryTest do
  use GitHoox.Case, async: false

  alias GitHoox.Runner

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  defp attach_collector(events) do
    ref = :telemetry_test.attach_event_handlers(self(), events)
    on_exit(fn -> :telemetry.detach(ref) end)
    ref
  end

  describe "hook events" do
    setup do
      ref =
        attach_collector([
          [:git_hoox, :hook, :start],
          [:git_hoox, :hook, :stop]
        ])

      %{ref: ref}
    end

    test "fire start + stop for a passing hook", %{repo: dir, ref: ref} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
      """)

      in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)

      assert_receive {[:git_hoox, :hook, :start], ^ref, %{system_time: _},
                      %{stage: :pre_commit, module: GitHoox.TestHooks.Pass, files: 1}}

      assert_receive {[:git_hoox, :hook, :stop], ^ref, %{duration: d},
                      %{stage: :pre_commit, module: GitHoox.TestHooks.Pass, result: :ok, error: nil}}

      assert is_integer(d) and d >= 0
    end

    test "fire stop with :error result + reason on failing hook", %{repo: dir, ref: ref} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: "nope"]}]]}
      """)

      in_repo(dir, fn -> assert {:error, _} = Runner.run(:pre_commit) end)

      assert_receive {[:git_hoox, :hook, :stop], ^ref, _,
                      %{module: GitHoox.TestHooks.Fail, result: :error, error: "nope"}}
    end

    test "fire stop with :skip when no files match the hook's glob", %{repo: dir, ref: ref} do
      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, files: ["lib/**/*.ex"]}]]}
      """)

      in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)

      assert_receive {[:git_hoox, :hook, :stop], ^ref, _,
                      %{module: GitHoox.TestHooks.Pass, result: :skip, files: 0}}
    end
  end

  describe "stage events" do
    setup do
      ref =
        attach_collector([
          [:git_hoox, :stage, :start],
          [:git_hoox, :stage, :stop]
        ])

      %{ref: ref}
    end

    test "stop carries aggregate result + counts", %{repo: dir, ref: ref} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [
        {GitHoox.TestHooks.Pass, []},
        {GitHoox.TestHooks.Fail, []}
      ]]}
      """)

      in_repo(dir, fn -> assert {:error, _} = Runner.run(:pre_commit) end)

      assert_receive {[:git_hoox, :stage, :stop], ^ref, %{duration: _},
                      %{stage: :pre_commit, entries: 2, files: 1, result: :error, failures: 1}}
    end

    test "ok result when all hooks pass", %{repo: dir, ref: ref} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
      """)

      in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)

      assert_receive {[:git_hoox, :stage, :stop], ^ref, _,
                      %{stage: :pre_commit, result: :ok, failures: 0}}
    end
  end
end
