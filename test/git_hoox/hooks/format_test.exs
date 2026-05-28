defmodule GitHoox.Hooks.FormatTest do
  use GitHoox.Case, async: false

  alias GitHoox.Hooks.Format

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp install_fake_mix(dir, script) do
    bin = Path.join(dir, "fake-bin")
    File.mkdir_p!(bin)
    path = Path.join(bin, "mix")
    File.write!(path, "#!/usr/bin/env sh\n" <> script)
    File.chmod!(path, 0o755)
    prior = System.get_env("PATH")
    System.put_env("PATH", bin <> ":" <> (prior || ""))
    on_exit(fn -> if prior, do: System.put_env("PATH", prior), else: System.delete_env("PATH") end)
  end

  test "default_opts/0 returns stage_fixed + glob list" do
    opts = Format.default_opts()
    assert opts[:stage_fixed] == true
    assert Enum.all?(opts[:files], &is_binary/1)
  end

  test "opts_schema/0 documents :check_only" do
    assert Keyword.has_key?(Format.opts_schema(), :check_only)
  end

  test "empty file list is a no-op" do
    assert :ok = Format.run([], [])
  end

  test "exit 0 returns {:ok, changed_in_worktree}", %{repo: dir} do
    install_fake_mix(dir, "exit 0\n")
    write(dir, "lib/foo.ex", "x\n")

    in_repo(dir, fn ->
      assert {:ok, []} = Format.run(["lib/foo.ex"], [])
    end)
  end

  test "non-zero exit returns {:error, {code, output}}", %{repo: dir} do
    install_fake_mix(dir, "echo bad-format >&2\nexit 1\n")
    write(dir, "lib/foo.ex", "x\n")

    in_repo(dir, fn ->
      assert {:error, {1, out}} = Format.run(["lib/foo.ex"], [])
      assert out =~ "bad-format"
    end)
  end

  test ":args splice between task and files", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    # Expect: format --dot-formatter custom.exs lib/foo.ex
    if [ "$1" = "format" ] && [ "$2" = "--dot-formatter" ] \
       && [ "$3" = "custom.exs" ] && [ "$4" = "lib/foo.ex" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 21
    """)

    write(dir, "lib/foo.ex", "x\n")

    in_repo(dir, fn ->
      assert {:ok, _} =
               Format.run(["lib/foo.ex"], args: ["--dot-formatter", "custom.exs"])
    end)
  end

  test ":args splice after --check-formatted when check_only", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "format" ] && [ "$2" = "--check-formatted" ] \
       && [ "$3" = "--dry-run" ] && [ "$4" = "lib/foo.ex" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 22
    """)

    write(dir, "lib/foo.ex", "x\n")

    in_repo(dir, fn ->
      assert {:ok, _} =
               Format.run(["lib/foo.ex"], check_only: true, args: ["--dry-run"])
    end)
  end

  test "check_only switches args to --check-formatted", %{repo: dir} do
    install_fake_mix(dir, """
    if [ "$2" = "--check-formatted" ]; then
      exit 0
    else
      echo "no check flag" >&2
      exit 99
    fi
    """)

    write(dir, "lib/foo.ex", "x\n")

    in_repo(dir, fn ->
      assert {:ok, _} = Format.run(["lib/foo.ex"], check_only: true)
    end)
  end
end
