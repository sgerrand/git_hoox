defmodule GitHoox.DoctorNonRepoTest do
  use ExUnit.Case, async: false

  alias GitHoox.Doctor

  setup do
    tmp = Path.join(System.tmp_dir!(), "git_hoox_no_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  test "all checks degrade gracefully outside a git repo", %{tmp: tmp} do
    checks = File.cd!(tmp, fn -> Doctor.run() end)

    by_name = fn name -> Enum.find(checks, &(&1.name == name)) end

    assert by_name.("git repository").status == :error
    assert by_name.("hooks directory").status == :error
    assert by_name.("shims").status == :error
    assert by_name.("config file").status == :warn
    assert by_name.("config validates").status == :warn
    assert Doctor.aggregate(checks) == :error
  end
end
