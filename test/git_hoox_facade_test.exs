defmodule GitHoox.FacadeTest do
  use GitHoox.Case, async: false

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  test "run/1 delegates to Runner.run/3", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
    """)

    in_repo(dir, fn ->
      assert :ok = GitHoox.run(:pre_commit)
    end)
  end
end
