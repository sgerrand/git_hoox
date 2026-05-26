defmodule GitHoox.InstallerHooksPathTest do
  use GitHoox.Case, async: false

  alias GitHoox.{Doctor, Installer}

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  describe "core.hooksPath" do
    test "install writes shims under the custom hooksPath", %{repo: dir} do
      custom = Path.join(dir, "custom-hooks")
      File.mkdir_p!(custom)
      set_config(dir, "core.hooksPath", custom)

      in_repo(dir, fn -> Installer.install() end)

      assert File.exists?(Path.join(custom, "pre-commit"))
      refute File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
    end

    test "shim retains the managed marker under custom hooksPath", %{repo: dir} do
      custom = Path.join(dir, "alt-hooks")
      File.mkdir_p!(custom)
      set_config(dir, "core.hooksPath", custom)

      in_repo(dir, fn -> Installer.install() end)

      content = File.read!(Path.join(custom, "pre-commit"))
      assert content =~ "# git_hoox managed"
    end

    test "uninstall removes shims from custom hooksPath", %{repo: dir} do
      custom = Path.join(dir, "alt-hooks")
      File.mkdir_p!(custom)
      set_config(dir, "core.hooksPath", custom)

      in_repo(dir, fn ->
        {:ok, _} = Installer.install()
        {:ok, _} = Installer.uninstall()
      end)

      refute File.exists?(Path.join(custom, "pre-commit"))
    end

    test "doctor reports the custom hooksPath", %{repo: dir} do
      custom = Path.join(dir, "alt-hooks")
      File.mkdir_p!(custom)
      set_config(dir, "core.hooksPath", custom)

      in_repo(dir, fn ->
        {:ok, _} = Installer.install()
      end)

      checks = in_repo(dir, fn -> Doctor.run() end)
      hooks_check = Enum.find(checks, &(&1.name == "hooks directory"))

      assert hooks_check.status == :ok
      assert hooks_check.detail =~ "alt-hooks"
    end
  end

  describe "linked worktrees" do
    setup do
      wt = Path.join(System.tmp_dir!(), "git_hoox_wt_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(wt) end)
      {:ok, wt: wt}
    end

    test "linked worktrees share the main repo's hooks dir by default", %{repo: dir, wt: wt} do
      worktree_add(dir, "feature", wt)

      in_repo(wt, fn -> Installer.install() end)

      assert File.exists?(Path.join(dir, ".git/hooks/pre-commit")),
             "git shares .git/hooks across worktrees — install from a worktree writes here"

      {out, 0} = sh(wt, ["rev-parse", "--git-path", "hooks"])
      hooks_dir = out |> String.trim() |> Path.expand(wt)
      refute String.contains?(hooks_dir, "worktrees")
    end

    test "per-worktree core.hooksPath isolates the worktree", %{repo: dir, wt: wt} do
      worktree_add(dir, "feature", wt)
      custom = Path.join(wt, "worktree-hooks")
      File.mkdir_p!(custom)
      set_config(wt, "core.hooksPath", custom)

      in_repo(wt, fn -> Installer.install() end)

      assert File.exists?(Path.join(custom, "pre-commit"))
      refute File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
    end

    test "doctor inside a linked worktree reports the shared hooks dir", %{repo: dir, wt: wt} do
      worktree_add(dir, "feature", wt)
      in_repo(wt, fn -> {:ok, _} = Installer.install() end)

      checks = in_repo(wt, fn -> Doctor.run() end)
      hooks_check = Enum.find(checks, &(&1.name == "hooks directory"))

      assert hooks_check.status == :ok
      assert hooks_check.detail =~ ".git/hooks"

      # Sanity: main worktree saw the shim
      assert File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
    end
  end
end
