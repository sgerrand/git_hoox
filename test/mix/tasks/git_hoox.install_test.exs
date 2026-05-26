defmodule Mix.Tasks.GitHoox.InstallTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.GitHoox.Install, as: InstallTask

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  test "default run installs 8 shims and prints summary", %{repo: dir} do
    out =
      capture_io(fn ->
        in_repo(dir, fn -> assert :ok = InstallTask.run([]) end)
      end)

    assert out =~ "git_hoox installed (8 shims)"
    assert File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
  end

  test "--dry-run prints planned entries and writes nothing", %{repo: dir} do
    out =
      capture_io(fn ->
        in_repo(dir, fn -> InstallTask.run(["--dry-run"]) end)
      end)

    assert out =~ "[write] "
    refute File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
  end

  test "--scaffold writes a starter config", %{repo: dir} do
    out =
      capture_io(fn ->
        in_repo(dir, fn -> InstallTask.run(["--scaffold"]) end)
      end)

    assert out =~ "git_hoox: wrote"
    assert File.exists?(Path.join(dir, ".git_hoox.exs"))
  end

  test "--scaffold --dry-run prints dry-run notice for config", %{repo: dir} do
    out =
      capture_io(fn ->
        in_repo(dir, fn -> InstallTask.run(["--scaffold", "--dry-run"]) end)
      end)

    assert out =~ "[scaffold] .git_hoox.exs (dry-run, not written)"
    refute File.exists?(Path.join(dir, ".git_hoox.exs"))
  end

  test "--scaffold over existing config prints error via Mix.shell", %{repo: dir} do
    File.write!(Path.join(dir, ".git_hoox.exs"), "%{hooks: []}")

    out =
      capture_io(:stderr, fn ->
        capture_io(fn ->
          in_repo(dir, fn -> InstallTask.run(["--scaffold"]) end)
        end)
      end)

    # Mix.shell().error writes to :stderr by default
    assert out =~ "already exists"
  end

  test "existing foreign hook without --force raises with formatted message", %{repo: dir} do
    path = Path.join(dir, ".git/hooks/pre-commit")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\necho user\n")

    assert_raise Mix.Error, ~r/--force/, fn ->
      capture_io(fn ->
        in_repo(dir, fn -> InstallTask.run([]) end)
      end)
    end
  end

  test "outside a git repo, install raises via catch-all format_error" do
    tmp = Path.join(System.tmp_dir!(), "no_repo_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    assert_raise Mix.Error, ~r/git_hoox install failed/, fn ->
      capture_io(:stderr, fn ->
        capture_io(fn ->
          File.cd!(tmp, fn -> InstallTask.run([]) end)
        end)
      end)
    end
  end
end
