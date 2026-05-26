defmodule GitHoox.Hooks.DialyzerTest do
  use GitHoox.Case, async: false

  alias GitHoox.Hooks.Dialyzer

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
    assert Dialyzer.default_opts()[:stage_fixed] == false
    assert Dialyzer.opts_schema() == []
  end

  test "exit 0 returns :ok", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "dialyzer" ] && [ "$2" = "--quiet" ]; then exit 0; fi
    echo "unexpected args" >&2
    exit 99
    """)

    in_repo(dir, fn ->
      assert :ok = Dialyzer.run(["lib/foo.ex"], [])
    end)
  end

  test "non-zero exit returns {:error, {code, output}}", %{repo: dir} do
    install_fake_mix(dir, "echo dialyzer-failed\nexit 4\n")

    in_repo(dir, fn ->
      assert {:error, {4, out}} = Dialyzer.run(["lib/foo.ex"], [])
      assert out =~ "dialyzer-failed"
    end)
  end
end
