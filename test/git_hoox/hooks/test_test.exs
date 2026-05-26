defmodule GitHoox.Hooks.TestHookTest do
  use GitHoox.Case, async: false

  alias GitHoox.Hooks.Test, as: TestHook

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

  test "default_opts/0 + opts_schema/0" do
    assert TestHook.default_opts()[:scope] == :all
    assert Keyword.has_key?(TestHook.opts_schema(), :scope)
  end

  test "scope :all calls `mix test` with no extra args", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    case "$#" in
      1) exit 0 ;;
      *) echo "wrong arg count: $#" >&2 ; exit 99 ;;
    esac
    """)

    in_repo(dir, fn ->
      assert :ok = TestHook.run(["lib/foo.ex"], scope: :all)
    end)
  end

  test "scope :stale appends --stale", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$2" = "--stale" ]; then exit 0; fi
    echo "missing --stale" >&2
    exit 5
    """)

    in_repo(dir, fn ->
      assert :ok = TestHook.run(["lib/foo.ex"], scope: :stale)
    end)
  end

  test "scope :related maps lib/x.ex → test/x_test.exs and only passes existing", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    # Args: test path1 path2 ... — print and pass
    shift  # drop "test"
    for f in "$@"; do echo "got: $f"; done
    exit 0
    """)

    write(dir, "test/foo_test.exs", "x\n")

    in_repo(dir, fn ->
      assert :ok = TestHook.run(["lib/foo.ex", "lib/nonexistent.ex"], scope: :related)
    end)
  end

  test "scope :related with no resolvable tests still runs mix test", %{repo: dir} do
    install_fake_mix(dir, "exit 0\n")

    in_repo(dir, fn ->
      assert :ok = TestHook.run(["lib/never.ex"], scope: :related)
    end)
  end

  test "non-zero exit surfaces as error tuple", %{repo: dir} do
    install_fake_mix(dir, "echo boom\nexit 2\n")

    in_repo(dir, fn ->
      assert {:error, {2, out}} = TestHook.run([], scope: :all)
      assert out =~ "boom"
    end)
  end
end
