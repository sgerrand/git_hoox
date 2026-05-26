defmodule GitHoox.LoggerTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureLog

  alias GitHoox.Runner

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  setup do
    GitHoox.Logger.attach()
    on_exit(fn -> GitHoox.Logger.detach() end)
    :ok
  end

  test "logs stage + hook stop events at info level on success", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    log =
      capture_log([level: :debug], fn ->
        in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)
      end)

    assert log =~ "[git_hoox] pre_commit → ok"
    assert log =~ "GitHoox.TestHooks.Pass → ok"
  end

  test "logs failures at warning level", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: "boom"]}]]}
    """)

    log =
      capture_log([level: :debug], fn ->
        in_repo(dir, fn -> assert {:error, _} = Runner.run(:pre_commit) end)
      end)

    assert log =~ "[git_hoox] pre_commit → error"
    assert log =~ "GitHoox.TestHooks.Fail → error"
    assert log =~ "reason: \"boom\""
  end

  test "attach is safe to call twice (returns {:error, :already_exists})" do
    assert {:error, :already_exists} = GitHoox.Logger.attach()
  end

  test "detach removes the handler" do
    assert :ok = GitHoox.Logger.detach()
    assert {:error, :not_found} = GitHoox.Logger.detach()
    # Re-attach so on_exit's detach finds something or simply errors quietly.
    GitHoox.Logger.attach()
  end
end
