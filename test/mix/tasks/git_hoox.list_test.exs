defmodule Mix.Tasks.GitHoox.ListTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  defp run_task(dir) do
    capture_io(fn ->
      in_repo(dir, fn -> Mix.Tasks.GitHoox.List.run([]) end)
    end)
  end

  test "prints stages, hooks, and merged opts", %{repo: dir} do
    write_config(dir, """
    %{
      hooks: [
        pre_commit: [
          {GitHoox.Hooks.Format, []},
          {GitHoox.Hooks.Credo, [strict: true]}
        ],
        pre_push: [
          {GitHoox.Hooks.Test, [scope: :stale]}
        ]
      ]
    }
    """)

    out = run_task(dir)

    assert out =~ "pre_commit:"
    assert out =~ "pre_push:"
    assert out =~ "GitHoox.Hooks.Format"
    assert out =~ "GitHoox.Hooks.Credo"
    assert out =~ "GitHoox.Hooks.Test"
    assert out =~ "strict: true"
    assert out =~ "scope: :stale"
    assert out =~ "stage_fixed: true"
  end

  test "shows defaults block", %{repo: dir} do
    write_config(dir, """
    %{
      hooks: [pre_commit: [{GitHoox.Hooks.Format, []}]],
      parallel: true,
      fail_fast: true
    }
    """)

    out = run_task(dir)
    assert out =~ "parallel:  true"
    assert out =~ "fail_fast: true"
    assert out =~ "skip_env:  GIT_HOOX"
  end

  test "missing config file raises", %{repo: dir} do
    assert_raise Mix.Error, ~r/Config not found/, fn ->
      capture_io(fn ->
        in_repo(dir, fn -> Mix.Tasks.GitHoox.List.run([]) end)
      end)
    end
  end
end
