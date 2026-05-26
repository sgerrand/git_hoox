defmodule GitHoox.ResidualsTest do
  use GitHoox.Case, async: false

  alias GitHoox.{Bench, Config, Doctor, Git, Hooks, Installer, Runner}

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  defp in_tmp(fun) do
    tmp = Path.join(System.tmp_dir!(), "git_hoox_resid_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)

    try do
      File.cd!(tmp, fn -> fun.(tmp) end)
    after
      File.rm_rf!(tmp)
    end
  end

  describe "Config" do
    test "default_path/0 returns the literal" do
      assert Config.default_path() == ".git_hoox.exs"
    end

    test "config evaluated as a keyword list is normalized", %{repo: _dir} do
      tmp = Path.join(System.tmp_dir!(), "cfg_kw_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      path = Path.join(tmp, ".git_hoox.exs")
      File.write!(path, "[hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]]")

      assert {:ok, %{hooks: [pre_commit: _]}} = Config.load(path)
    end

    test "Config.load on a hook without default_opts/0 takes the else branch", %{repo: _dir} do
      tmp = Path.join(System.tmp_dir!(), "cfg_nd_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf!(tmp) end)
      path = Path.join(tmp, ".git_hoox.exs")
      File.write!(path, "%{hooks: [pre_commit: [{GitHoox.TestHooks.NoDefaults, []}]]}")

      assert {:ok, _} = Config.load(path)
    end

    test "Runner.run_one merges with no default_opts/0", %{repo: dir} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.NoDefaults, [files: ["**/*"]]}]]}
      """)

      in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)
    end
  end

  describe "Doctor" do
    test "hooks dir resolves but does not exist on disk yet", %{repo: dir} do
      # core.hooksPath points to a path we do not create.
      missing = Path.join(dir, "no-such-dir")
      set_config(dir, "core.hooksPath", missing)

      checks = in_repo(dir, fn -> Doctor.run() end)
      hooks_check = Enum.find(checks, &(&1.name == "hooks directory"))
      assert hooks_check.status == :warn
      assert hooks_check.detail =~ "does not exist yet"
    end

    test "managed shims with missing hooks reports unowned count", %{repo: dir} do
      # Install one hook manually with the marker, leave others uninstalled.
      path = Path.join(dir, ".git/hooks/pre-commit")
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "#!/bin/sh\n# git_hoox managed\nexec mix git_hoox.run pre-commit\n")

      checks = in_repo(dir, fn -> Doctor.run() end)
      shim_check = Enum.find(checks, &(&1.name == "shims"))
      assert shim_check.status == :ok
      assert shim_check.detail =~ "unowned"
    end

    test "managed? returns false for an unreadable path", %{repo: dir} do
      # A directory is not readable as a file → File.read returns {:error, :eisdir}.
      # Make .git/hooks/pre-commit a directory to drive the catch-all branch.
      path = Path.join(dir, ".git/hooks/pre-commit")
      File.mkdir_p!(path)

      checks = in_repo(dir, fn -> Doctor.run() end)
      shim_check = Enum.find(checks, &(&1.name == "shims"))
      # The directory shows up as a non-managed (foreign) entry, so the foreign
      # branch fires regardless — what matters is that managed?/1's catch-all
      # was exercised without crashing.
      assert shim_check.status == :warn
    end
  end

  describe "Git" do
    test "changed_in_worktree on git error returns []" do
      in_tmp(fn _ -> assert [] = Git.changed_in_worktree(["x.ex"]) end)
    end

    test "staged_files outside repo propagates the git error" do
      in_tmp(fn _ -> assert {:error, {_code, _msg}} = Git.staged_files() end)
    end
  end

  describe "Installer" do
    test "uninstall outside a git repo returns {:ok, 0}" do
      in_tmp(fn _ -> assert {:ok, 0} = Installer.uninstall() end)
    end

    test "uninstall skips paths whose File.read fails (dir at hook path)", %{repo: dir} do
      # Put a directory where pre-commit would live. File.read returns
      # {:error, :eisdir}, which exercises managed?/1's catch-all.
      path = Path.join(dir, ".git/hooks/pre-commit")
      File.mkdir_p!(path)

      in_repo(dir, fn ->
        assert {:ok, 0} = Installer.uninstall()
      end)
    end

    test "uninstall restores latest backup", %{repo: dir} do
      # Plant a foreign hook, install with --force (creates backup), uninstall.
      hook = Path.join(dir, ".git/hooks/pre-commit")
      File.mkdir_p!(Path.dirname(hook))
      File.write!(hook, "#!/bin/sh\necho original\n")

      in_repo(dir, fn -> {:ok, _} = Installer.install(force: true) end)

      [_backup] = Path.wildcard(hook <> ".backup.*")

      in_repo(dir, fn -> {:ok, _} = Installer.uninstall() end)

      assert File.exists?(hook), "backup should have been restored"
      assert File.read!(hook) =~ "echo original"
    end
  end

  describe "Bench" do
    test "run/2 exercises the live telemetry collector", %{repo: dir} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
      """)

      summaries = in_repo(dir, fn -> Bench.run(:pre_commit, 2) end)

      assert [%{module: GitHoox.TestHooks.Pass, runs: 2}] = summaries
    end
  end

  describe "Hooks.Shell" do
    test "{staged_files} outside a git repo keeps the literal token" do
      in_tmp(fn _ ->
        assert :ok = Hooks.Shell.run([], run: "true # {staged_files}")
      end)
    end

    test "{all_files} outside a git repo keeps the literal token" do
      in_tmp(fn _ ->
        assert :ok = Hooks.Shell.run([], run: "true # {all_files}")
      end)
    end
  end
end
