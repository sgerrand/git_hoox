defmodule Mix.Tasks.GitHoox.DoctorTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.GitHoox.Doctor, as: DoctorTask

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  test "warn-level checks exit 0 with [ok] / [warn] labels", %{repo: dir} do
    out =
      capture_io(fn ->
        in_repo(dir, fn -> assert :ok = DoctorTask.run([]) end)
      end)

    assert out =~ "[ok]"
    assert out =~ "[warn]"
    assert out =~ "git repository"
  end

  test "error-level check exits 1 via :shutdown", %{repo: dir} do
    File.write!(Path.join(dir, ".git_hoox.exs"), "%{hooks: [bogus_stage: []]}")

    assert {:shutdown, 1} =
             catch_exit(
               capture_io(fn ->
                 in_repo(dir, fn -> DoctorTask.run([]) end)
               end)
             )
  end

  test "output renders [fail] label for error checks", %{repo: dir} do
    File.write!(Path.join(dir, ".git_hoox.exs"), "%{hooks: [bogus_stage: []]}")

    out =
      capture_io(fn ->
        catch_exit(in_repo(dir, fn -> DoctorTask.run([]) end))
      end)

    assert out =~ "[fail]"
  end
end
