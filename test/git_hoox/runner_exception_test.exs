defmodule GitHoox.RunnerExceptionTest do
  use GitHoox.Case, async: false

  alias GitHoox.Runner

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  defp attach_collector(events) do
    handler_id = "test-exc-#{System.unique_integer([:positive])}"
    pid = self()

    :telemetry.attach_many(
      handler_id,
      events,
      fn ev, meas, meta, _ -> send(pid, {:telemetry, ev, meas, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  setup do
    attach_collector([
      [:git_hoox, :hook, :start],
      [:git_hoox, :hook, :stop],
      [:git_hoox, :hook, :exception]
    ])
  end

  test "hook that raises emits :exception (not :stop) and surfaces as :crashed", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Raiser, [raise_as: :error]}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, [{GitHoox.TestHooks.Raiser, {:error, {:crashed, _}}}]} =
               Runner.run(:pre_commit)
    end)

    assert_receive {:telemetry, [:git_hoox, :hook, :exception], %{duration: _},
                    %{module: GitHoox.TestHooks.Raiser, kind: kind, reason: _, stacktrace: _}}

    assert kind in [:error, :exit]
    refute_received {:telemetry, [:git_hoox, :hook, :stop], _, %{module: GitHoox.TestHooks.Raiser}}
  end

  test "hook that exits emits :exception with kind :exit", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Raiser, [raise_as: :exit]}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, [{GitHoox.TestHooks.Raiser, {:error, {:crashed, _}}}]} =
               Runner.run(:pre_commit)
    end)

    assert_receive {:telemetry, [:git_hoox, :hook, :exception], _,
                    %{module: GitHoox.TestHooks.Raiser, kind: :exit}}
  end

  test "hook that throws emits :exception", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Raiser, [raise_as: :throw]}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, _} = Runner.run(:pre_commit)
    end)

    assert_receive {:telemetry, [:git_hoox, :hook, :exception], _,
                    %{module: GitHoox.TestHooks.Raiser}}
  end

  test "hook timeout emits :exception with the timeout reason", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Slow, timeout: 50, sleep_ms: 500}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, [{GitHoox.TestHooks.Slow, {:error, {:timeout, 50}}}]} =
               Runner.run(:pre_commit)
    end)

    assert_receive {:telemetry, [:git_hoox, :hook, :exception], _,
                    %{module: GitHoox.TestHooks.Slow, kind: :exit, reason: {:git_hoox_timeout, 50}}}
  end

  test "normal :error return still emits :stop (not :exception)", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: "regular fail"]}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, _} = Runner.run(:pre_commit)
    end)

    assert_receive {:telemetry, [:git_hoox, :hook, :stop], _,
                    %{module: GitHoox.TestHooks.Fail, result: :error, error: "regular fail"}}

    refute_received {:telemetry, [:git_hoox, :hook, :exception], _,
                     %{module: GitHoox.TestHooks.Fail}}
  end
end
