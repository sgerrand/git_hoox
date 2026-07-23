defmodule GitHoox.Hooks.CredoTest do
  use GitHoox.Case, async: false

  alias GitHoox.Hooks.Credo

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

  test "default_opts/0 + opts_schema/0 expose strict knob" do
    assert Credo.default_opts()[:stage_fixed] == false
    assert Keyword.has_key?(Credo.opts_schema(), :strict)
  end

  test "empty file list short-circuits" do
    assert :ok = Credo.run([], [])
  end

  test "exit 0 returns :ok", %{repo: dir} do
    install_fake_mix(dir, "exit 0\n")

    in_repo(dir, fn ->
      assert :ok = Credo.run(["lib/foo.ex"], [])
    end)
  end

  test "non-zero exit returns {:error, {code, output}}", %{repo: dir} do
    install_fake_mix(dir, "echo credo-failed\nexit 3\n")

    in_repo(dir, fn ->
      assert {:error, {3, out}} = Credo.run(["lib/foo.ex"], [])
      assert out =~ "credo-failed"
    end)
  end

  test ":args splice between --strict and the file list", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    # Expect: credo --strict --format json -- lib/foo.ex
    if [ "$1" = "credo" ] && [ "$2" = "--strict" ] \
       && [ "$3" = "--format" ] && [ "$4" = "json" ] \
       && [ "$5" = "--" ] && [ "$6" = "lib/foo.ex" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 31
    """)

    in_repo(dir, fn ->
      assert :ok =
               Credo.run(["lib/foo.ex"], strict: true, args: ["--format", "json"])
    end)
  end

  test "-- separator neutralizes dash-leading filenames", %{repo: dir} do
    # A git-supplied filename beginning with `-` must reach credo as a
    # positional path (after `--`), never as a switch like --config-file=...
    install_fake_mix(dir, ~S"""
    if [ "$1" = "credo" ] && [ "$2" = "--" ] \
       && [ "$3" = "--config-file=/evil.exs" ]; then
      exit 0
    fi
    echo "unexpected args: $@" >&2
    exit 33
    """)

    in_repo(dir, fn ->
      assert :ok = Credo.run(["--config-file=/evil.exs"], [])
    end)
  end

  test "strict: true inserts --strict before positional files", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    strict_pos=""
    files_pos=""
    i=0
    for arg in "$@"; do
      i=$((i + 1))
      case "$arg" in
        --strict) strict_pos=$i ;;
        --files-included) files_pos=$i ;;
      esac
    done
    if [ -z "$strict_pos" ]; then
      echo "no strict: $*" >&2 ; exit 7
    fi
    if [ -z "$files_pos" ]; then
      echo "no --files-included: $*" >&2 ; exit 8
    fi
    if [ "$strict_pos" -lt "$files_pos" ]; then
      exit 0
    fi
    echo "strict after files: $*" >&2 ; exit 9
    """)

    in_repo(dir, fn ->
      assert :ok = Credo.run(["lib/foo.ex"], strict: true)
    end)
  end
end
