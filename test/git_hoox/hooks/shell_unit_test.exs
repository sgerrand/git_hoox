defmodule GitHoox.Hooks.ShellUnitTest do
  use ExUnit.Case, async: true

  alias GitHoox.Hooks.Shell

  test "missing :run option returns an error tuple" do
    assert {:error, msg} = Shell.run(["x"], [])
    assert msg =~ ":run"
  end

  test "{push_files} outside :pre_push stage returns an error" do
    for stage <- [:pre_commit, :commit_msg, :post_merge, nil] do
      opts = [run: "echo {push_files}", __stage__: stage]
      assert {:error, msg} = Shell.run(["x"], opts)
      assert msg =~ "pre_push"
    end
  end

  test "default_opts/0 + opts_schema/0 are stable" do
    assert Shell.default_opts() == [stage_fixed: false, files: ["**/*"]]
    schema = Shell.opts_schema()
    assert Keyword.has_key?(schema, :run)
    assert Keyword.has_key?(schema, :shell)
  end
end
