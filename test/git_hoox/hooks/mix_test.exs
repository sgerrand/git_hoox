defmodule GitHoox.Hooks.MixTest do
  use GitHoox.Case, async: false

  alias GitHoox.Hooks.Mix, as: MixHook

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
    defaults = MixHook.default_opts()
    assert defaults[:stage_fixed] == false
    # :files must be set — Runner.run_one/3 reads it via Keyword.fetch!/2
    # and the global schema default ("**/*") is not propagated into runtime
    # opts, so hooks have to declare it themselves.
    assert defaults[:files] == ["**/*"]

    schema = MixHook.opts_schema()
    assert Keyword.has_key?(schema, :task)
    assert Keyword.has_key?(schema, :args)
    assert Keyword.has_key?(schema, :append_files)
  end

  test "missing :task surfaces explicit error" do
    assert {:error, msg} = MixHook.run([], [])
    assert msg =~ ":task"
  end

  test "runs mix <task> when :task given", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "docs" ] && [ "$#" = "1" ]; then exit 0; fi
    echo "unexpected args: $@" >&2
    exit 5
    """)

    in_repo(dir, fn ->
      assert :ok = MixHook.run([], task: "docs")
    end)
  end

  test ":args splice after task name", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "compile" ] && [ "$2" = "--warnings-as-errors" ]; then exit 0; fi
    echo "unexpected args: $@" >&2
    exit 7
    """)

    in_repo(dir, fn ->
      assert :ok = MixHook.run([], task: "compile", args: ["--warnings-as-errors"])
    end)
  end

  test ":append_files appends matched files after --", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    # Expect: lint --quiet -- lib/foo.ex lib/bar.ex
    if [ "$1" = "lint" ] && [ "$2" = "--quiet" ] && [ "$3" = "--" ] \
       && [ "$4" = "lib/foo.ex" ] && [ "$5" = "lib/bar.ex" ]; then
      exit 0
    fi
    echo "unexpected: $@" >&2
    exit 9
    """)

    in_repo(dir, fn ->
      assert :ok =
               MixHook.run(["lib/foo.ex", "lib/bar.ex"],
                 task: "lint",
                 args: ["--quiet"],
                 append_files: true
               )
    end)
  end

  test ":append_files puts a dash-leading filename after --", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    # A file named --version must land after the terminator, not before.
    if [ "$1" = "lint" ] && [ "$2" = "--" ] && [ "$3" = "--version" ]; then
      exit 0
    fi
    echo "unexpected: $@" >&2
    exit 10
    """)

    in_repo(dir, fn ->
      assert :ok = MixHook.run(["--version"], task: "lint", append_files: true)
    end)
  end

  test ":append_files true with empty file list short-circuits to :ok", %{repo: dir} do
    install_fake_mix(dir, "echo SHOULD_NOT_RUN >&2\nexit 11\n")

    in_repo(dir, fn ->
      assert :ok = MixHook.run([], task: "lint", append_files: true)
    end)
  end

  test ":append_files false runs task even with empty file list", %{repo: dir} do
    install_fake_mix(dir, ~S"""
    if [ "$1" = "docs" ]; then exit 0; fi
    exit 13
    """)

    in_repo(dir, fn ->
      assert :ok = MixHook.run([], task: "docs", append_files: false)
    end)
  end

  test "non-zero exit returns {:error, {code, output}}", %{repo: dir} do
    install_fake_mix(dir, "echo doc-broken >&2\nexit 2\n")

    in_repo(dir, fn ->
      assert {:error, {2, out}} = MixHook.run([], task: "docs")
      assert out =~ "doc-broken"
    end)
  end
end
