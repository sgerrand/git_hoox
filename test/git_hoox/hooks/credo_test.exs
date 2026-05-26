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

  test "strict: true inserts --strict before --files-included", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    seen=""
    for arg in "$@"; do
      seen="$seen $arg"
    done
    case "$seen" in
      *" --strict "*) exit 0 ;;
      *) echo "no strict: $seen" >&2 ; exit 7 ;;
    esac
    """)

    in_repo(dir, fn ->
      assert :ok = Credo.run(["lib/foo.ex"], strict: true)
    end)
  end
end
