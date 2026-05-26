defmodule Mix.Tasks.GitHoox.UninstallTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias GitHoox.Installer
  alias Mix.Tasks.GitHoox.Uninstall, as: UninstallTask

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  test "removes installed shims and prints summary", %{repo: dir} do
    in_repo(dir, fn -> {:ok, _} = Installer.install() end)

    out =
      capture_io(fn ->
        in_repo(dir, fn -> assert :ok = UninstallTask.run([]) end)
      end)

    assert out =~ "git_hoox: removed"
    refute File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
  end
end
