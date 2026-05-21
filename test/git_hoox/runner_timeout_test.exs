defmodule GitHoox.RunnerTimeoutTest do
  use GitHoox.Case, async: false

  alias GitHoox.Runner

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  test "hook exceeding :timeout is killed and reported as timeout error", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Slow, timeout: 100, sleep_ms: 1000}]]}
    """)

    in_repo(dir, fn ->
      assert {:error, [{GitHoox.TestHooks.Slow, {:error, {:timeout, 100}}}]} =
               Runner.run(:pre_commit)
    end)
  end

  test "hook within :timeout succeeds", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Slow, timeout: 1000, sleep_ms: 50}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = Runner.run(:pre_commit)
    end)
  end
end
