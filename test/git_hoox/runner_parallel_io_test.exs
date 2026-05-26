defmodule GitHoox.RunnerParallelIoTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias GitHoox.Runner

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  setup do
    Application.put_env(:git_hoox, :stream_output, true)
    on_exit(fn -> Application.put_env(:git_hoox, :stream_output, false) end)
    :ok
  end

  test "parallel hooks do not interleave each other's stdout", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    # Each Shell hook prints a 50-line block. Without the per-task capture
    # buffer, BEAM ports interleave their chunks on the real device and
    # AAA / BBB lines mix together. With the fix, each block is flushed
    # atomically once the hook finishes.
    write_config(dir, """
    %{
      hooks: [pre_commit: [
        {GitHoox.Hooks.Shell, run: "for i in $(seq 1 50); do echo AAA_$i; done"},
        {GitHoox.Hooks.Shell, run: "for i in $(seq 1 50); do echo BBB_$i; done"}
      ]],
      parallel: true
    }
    """)

    out =
      capture_io(fn ->
        in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)
      end)

    lines =
      out
      |> String.split("\n", trim: true)
      |> Enum.filter(&(&1 =~ ~r/^(AAA|BBB)_\d+$/))

    assert length(lines) == 100, "expected 100 marker lines, got #{length(lines)}"

    # After the fix, every AAA line precedes every BBB line, or vice
    # versa — they form two contiguous blocks rather than being mixed.
    prefixes = Enum.map(lines, &String.slice(&1, 0..2))
    transitions = Enum.zip(prefixes, tl(prefixes)) |> Enum.count(fn {a, b} -> a != b end)

    assert transitions == 1,
           "expected exactly one prefix transition (one contiguous block per hook), got #{transitions}.\n#{Enum.join(lines, "\n")}"
  end

  test "serial mode still streams chunk by chunk", %{repo: dir} do
    write(dir, "lib/foo.ex", "x\n")
    stage(dir, ["lib/foo.ex"])

    write_config(dir, """
    %{
      hooks: [pre_commit: [
        {GitHoox.Hooks.Shell, run: "echo serial-line"}
      ]],
      parallel: false
    }
    """)

    out =
      capture_io(fn ->
        in_repo(dir, fn -> assert :ok = Runner.run(:pre_commit) end)
      end)

    assert out =~ "serial-line"
  end
end
