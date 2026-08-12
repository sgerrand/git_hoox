defmodule GitHoox.InstallerTest do
  use GitHoox.Case, async: false

  alias GitHoox.Installer

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  test "writes shims with marker + exec bit", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, _plan} = Installer.install()
    end)

    path = Path.join(dir, ".git/hooks/pre-commit")
    assert File.exists?(path)
    content = File.read!(path)
    assert content =~ "# git_hoox managed"
    assert content =~ "mix git_hoox.run pre-commit"

    %{mode: mode} = File.stat!(path)
    assert Bitwise.band(mode, 0o111) != 0
  end

  test "default shim has no deps.get prelude", %{repo: dir} do
    in_repo(dir, fn -> Installer.install() end)

    content = File.read!(Path.join(dir, ".git/hooks/pre-commit"))
    refute content =~ "mix deps.get"
  end

  test "auto_deps_get prepends a deps.get self-heal line", %{repo: dir} do
    in_repo(dir, fn -> Installer.install(auto_deps_get: true) end)

    content = File.read!(Path.join(dir, ".git/hooks/pre-commit"))
    assert content =~ "# git_hoox managed"
    assert content =~ "mix deps.get --check-locked >/dev/null 2>&1 || mix deps.get"
    assert content =~ "exec mix git_hoox.run pre-commit"
    # prelude must run before the exec line replaces the process
    assert :binary.match(content, "mix deps.get --check-locked") <
             :binary.match(content, "exec mix git_hoox.run")
  end

  test "installs all stages", %{repo: dir} do
    in_repo(dir, fn -> Installer.install() end)

    for hook <- ~w(pre-commit prepare-commit-msg commit-msg post-commit
                   pre-rebase post-checkout post-merge pre-push) do
      assert File.exists?(Path.join(dir, ".git/hooks/#{hook}")),
             "missing #{hook}"
    end
  end

  test "refuses existing user hook without --force", %{repo: dir} do
    path = Path.join(dir, ".git/hooks/pre-commit")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\necho user hook\n")
    File.chmod!(path, 0o755)

    in_repo(dir, fn ->
      assert {:error, {:exists, returned_path, msg}} = Installer.install()
      assert String.ends_with?(returned_path, ".git/hooks/pre-commit")
      assert msg =~ "--force"
    end)

    assert File.read!(path) == "#!/bin/sh\necho user hook\n"
  end

  # An existing path that cannot be read must not be mistaken for a free
  # slot. A directory is used here because it fails File.read/1 for every
  # user, including root, unlike a chmod 000 file.
  test "refuses an existing but unreadable hook without --force", %{repo: dir} do
    path = Path.join(dir, ".git/hooks/pre-commit")
    File.mkdir_p!(path)

    in_repo(dir, fn ->
      assert {:error, {:exists, returned_path, msg}} = Installer.install()
      assert String.ends_with?(returned_path, ".git/hooks/pre-commit")
      assert msg =~ "could not be read"
      assert msg =~ "--force"
    end)

    assert File.dir?(path), "unreadable hook should be left untouched"
  end

  test "--force backs up existing user hook", %{repo: dir} do
    path = Path.join(dir, ".git/hooks/pre-commit")
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "#!/bin/sh\necho user\n")

    in_repo(dir, fn -> Installer.install(force: true) end)

    [backup] = Path.wildcard(path <> ".backup.*")
    assert File.read!(backup) =~ "echo user"
    assert File.read!(path) =~ "git_hoox managed"
  end

  test "re-install over own shim does not require --force", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, _} = Installer.install()
      assert {:ok, _} = Installer.install()
    end)

    path = Path.join(dir, ".git/hooks/pre-commit")
    assert [] = Path.wildcard(path <> ".backup.*")
  end

  test "dry-run writes nothing", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, plan} = Installer.install(dry_run: true)
      assert is_list(plan)
    end)

    refute File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
  end

  test "scaffold writes .git_hoox.exs at repo root", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, path} = Installer.scaffold()
      assert String.ends_with?(path, ".git_hoox.exs")
    end)

    content = File.read!(Path.join(dir, ".git_hoox.exs"))
    assert content =~ "GitHoox.Hooks.Format"
    assert content =~ "GitHoox.Hooks.Credo"
    assert content =~ "GitHoox.Hooks.Test"
    assert content =~ "pre_commit:"
    assert content =~ "pre_push:"
  end

  test "scaffold refuses to overwrite existing config", %{repo: dir} do
    path = Path.join(dir, ".git_hoox.exs")
    File.write!(path, "# user config")

    in_repo(dir, fn ->
      assert {:error, {:config_exists, returned}} = Installer.scaffold()
      assert String.ends_with?(returned, ".git_hoox.exs")
    end)

    assert File.read!(path) == "# user config"
  end

  test "scaffold --force overwrites existing config", %{repo: dir} do
    path = Path.join(dir, ".git_hoox.exs")
    File.write!(path, "# user config")

    in_repo(dir, fn ->
      assert {:ok, _} = Installer.scaffold(force: true)
    end)

    refute File.read!(path) =~ "user config"
    assert File.read!(path) =~ "GitHoox.Hooks.Format"
  end

  test "scaffolded config parses cleanly via Config.load", %{repo: dir} do
    in_repo(dir, fn ->
      assert {:ok, _} = Installer.scaffold()
      assert {:ok, config} = GitHoox.Config.load()
      assert config.parallel == false
      assert Keyword.has_key?(config.hooks, :pre_commit)
      assert Keyword.has_key?(config.hooks, :pre_push)
    end)
  end

  test "uninstall ignores backup siblings without ISO8601 suffix", %{repo: dir} do
    hook = Path.join(dir, ".git/hooks/pre-commit")
    File.mkdir_p!(Path.dirname(hook))
    File.write!(hook, "#!/bin/sh\necho original\n")

    in_repo(dir, fn -> {:ok, _} = Installer.install(force: true) end)

    [real_backup] = Path.wildcard(hook <> ".backup.*")
    # Plant a stray file whose name sorts after the real backup but is not
    # a managed backup. latest_backup/1 must skip it.
    stray = hook <> ".backup.zzz"
    File.write!(stray, "not a backup")

    in_repo(dir, fn -> {:ok, _} = Installer.uninstall() end)

    assert File.read!(hook) =~ "echo original",
           "expected #{real_backup} to be restored, not #{stray}"

    assert File.exists?(stray), "stray sibling should remain on disk"
  end

  test "uninstall removes only managed shims", %{repo: dir} do
    user_hook = Path.join(dir, ".git/hooks/commit-msg")
    File.mkdir_p!(Path.dirname(user_hook))
    File.write!(user_hook, "#!/bin/sh\necho user\n")
    File.chmod!(user_hook, 0o755)

    in_repo(dir, fn ->
      {:ok, _} = Installer.install(force: true)
      {:ok, _count} = Installer.uninstall()
    end)

    refute File.exists?(Path.join(dir, ".git/hooks/pre-commit"))
    assert File.read!(user_hook) =~ "echo user"
  end
end
