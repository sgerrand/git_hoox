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

  test "scope :related skips mix test entirely when no related tests exist", %{repo: dir} do
    install_fake_mix(dir, "echo SHOULD_NOT_RUN >&2\nexit 7\n")

    in_repo(dir, fn ->
      assert :ok = TestHook.run(["lib/never.ex"], scope: :related)
    end)
  end

  test ":args splice after `test` for scope :all", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "test" ] && [ "$2" = "--warnings-as-errors" ]; then exit 0; fi
    echo "unexpected args: $@" >&2
    exit 11
    """)

    in_repo(dir, fn ->
      assert :ok = TestHook.run([], scope: :all, args: ["--warnings-as-errors"])
    end)
  end

  test ":args splice after --stale for scope :stale", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "test" ] && [ "$2" = "--stale" ] && [ "$3" = "--warnings-as-errors" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 12
    """)

    in_repo(dir, fn ->
      assert :ok = TestHook.run([], scope: :stale, args: ["--warnings-as-errors"])
    end)
  end

  test ":args precede related test files for scope :related", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "test" ] && [ "$2" = "--warnings-as-errors" ] \
       && [ "$3" = "--" ] && [ "$4" = "test/foo_test.exs" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 13
    """)

    write(dir, "test/foo_test.exs", "x\n")

    in_repo(dir, fn ->
      assert :ok =
               TestHook.run(["lib/foo.ex"],
                 scope: :related,
                 args: ["--warnings-as-errors"]
               )
    end)
  end

  test "-- separator neutralizes dash-leading related paths", %{repo: dir} do
    # A related test path beginning with `-` must reach mix test as a
    # positional path (after `--`), never as an option.
    install_fake_mix(dir, ~S"""
    if [ "$1" = "test" ] && [ "$2" = "--" ] \
       && [ "$3" = "--evil_test.exs" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 14
    """)

    write(dir, "--evil_test.exs", "x\n")

    in_repo(dir, fn ->
      assert :ok = TestHook.run(["--evil.ex"], scope: :related)
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
