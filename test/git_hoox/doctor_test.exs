defmodule GitHoox.DoctorTest do
  use GitHoox.Case, async: false

  alias GitHoox.Doctor

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp by_name(checks, name) do
    Enum.find(checks, fn c -> c.name == name end)
  end

  test "fresh repo with no shims and no config", %{repo: dir} do
    checks = in_repo(dir, fn -> Doctor.run() end)

    assert by_name(checks, "git repository").status == :ok
    assert by_name(checks, "shims").status == :warn
    assert by_name(checks, "config file").status == :warn
    assert by_name(checks, "config validates").status == :warn
    assert Doctor.aggregate(checks) == :warn
  end

  test "installed shims + valid config = all ok", %{repo: dir} do
    in_repo(dir, fn ->
      {:ok, _} = GitHoox.Installer.install()
      {:ok, _} = GitHoox.Installer.scaffold()
    end)

    checks = in_repo(dir, fn -> Doctor.run() end)

    assert by_name(checks, "git repository").status == :ok
    assert by_name(checks, "shims").status == :ok
    assert by_name(checks, "config file").status == :ok
    assert by_name(checks, "config validates").status == :ok
    assert Doctor.aggregate(checks) == :ok
  end

  test "foreign hook present surfaces as warn", %{repo: dir} do
    path = Path.join(dir, ".git/hooks/pre-commit")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\necho user\n")

    checks = in_repo(dir, fn -> Doctor.run() end)

    shim_check = by_name(checks, "shims")
    assert shim_check.status == :warn
    assert shim_check.detail =~ "foreign"
  end

  test "managed shim without exec bit surfaces as error", %{repo: dir} do
    in_repo(dir, fn -> {:ok, _} = GitHoox.Installer.install() end)

    pre_commit = Path.join(dir, ".git/hooks/pre-commit")
    File.chmod!(pre_commit, 0o644)

    checks = in_repo(dir, fn -> Doctor.run() end)

    shim_check = by_name(checks, "shims")
    assert shim_check.status == :error
    assert shim_check.detail =~ "executable bit"
    assert shim_check.detail =~ "pre-commit"
    assert Doctor.aggregate(checks) == :error
  end

  test "invalid config surfaces as error", %{repo: dir} do
    File.write!(Path.join(dir, ".git_hoox.exs"), "%{hooks: [bogus_stage: []]}")

    checks = in_repo(dir, fn -> Doctor.run() end)

    valid_check = by_name(checks, "config validates")
    assert valid_check.status == :error
    assert Doctor.aggregate(checks) == :error
  end

  test "aggregate prioritises error over warn over ok" do
    assert Doctor.aggregate([%{status: :ok, name: "a", detail: ""}]) == :ok

    assert Doctor.aggregate([
             %{status: :ok, name: "a", detail: ""},
             %{status: :warn, name: "b", detail: ""}
           ]) == :warn

    assert Doctor.aggregate([
             %{status: :warn, name: "a", detail: ""},
             %{status: :error, name: "b", detail: ""}
           ]) == :error
  end
end
