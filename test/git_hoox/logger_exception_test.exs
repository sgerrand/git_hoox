defmodule GitHoox.LoggerExceptionTest do
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

  test "hook exception logs at error level via the exception handler", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Raiser, [raise_as: :error]}]]}
    """)

    log =
      capture_log([level: :debug], fn ->
        in_repo(dir, fn -> assert {:error, _} = Runner.run(:pre_commit) end)
      end)

    assert log =~ "GitHoox.TestHooks.Raiser → exception"
  end
end
