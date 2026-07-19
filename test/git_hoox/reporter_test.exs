defmodule GitHoox.ReporterTest do
  use GitHoox.Case, async: false

  import ExUnit.CaptureIO

  alias GitHoox.Reporter
  alias GitHoox.Runner
  alias Mix.Tasks.GitHoox.Run, as: RunTask

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  defp write_config(dir, body) do
    File.write!(Path.join(dir, ".git_hoox.exs"), body)
  end

  # native time units for a given millisecond count, so format_duration
  # round-trips back to the same ms.
  defp native_ms(ms), do: System.convert_time_unit(ms, :millisecond, :native)

  defp fire(event, measurements, meta) do
    capture_io(fn -> :telemetry.execute(event, measurements, meta) end)
  end

  setup do
    on_exit(fn -> Reporter.detach() end)
    :ok
  end

  describe "stage lines" do
    setup do
      Reporter.attach(color: false)
      :ok
    end

    test "start prints header with pluralised counts" do
      out =
        fire([:git_hoox, :stage, :start], %{system_time: 0}, %{
          stage: :pre_commit,
          entries: 3,
          files: 5
        })

      assert out == "→ pre-commit · 3 hooks · 5 files\n"
    end

    test "start with a single hook and file is singular" do
      out =
        fire([:git_hoox, :stage, :start], %{system_time: 0}, %{
          stage: :pre_push,
          entries: 1,
          files: 1
        })

      assert out == "→ pre-push · 1 hook · 1 file\n"
    end

    test "start with zero entries prints nothing" do
      out =
        fire([:git_hoox, :stage, :start], %{system_time: 0}, %{
          stage: :pre_commit,
          entries: 0,
          files: 5
        })

      assert out == ""
    end

    test "stop ok prints green summary" do
      out =
        fire([:git_hoox, :stage, :stop], %{duration: native_ms(1200)}, %{
          stage: :pre_commit,
          entries: 3,
          files: 5,
          result: :ok,
          failures: 0
        })

      assert out == "✓ pre-commit · 3 hooks · 1.2s\n"
    end

    test "stop error prints failed count" do
      out =
        fire([:git_hoox, :stage, :stop], %{duration: native_ms(1500)}, %{
          stage: :pre_commit,
          entries: 3,
          files: 5,
          result: :error,
          failures: 1
        })

      assert out == "✗ pre-commit · 1/3 failed · 1.5s\n"
    end

    test "stop with zero entries prints nothing" do
      out =
        fire([:git_hoox, :stage, :stop], %{duration: native_ms(10)}, %{
          stage: :pre_commit,
          entries: 0,
          files: 0,
          result: :ok,
          failures: 0
        })

      assert out == ""
    end

    test "exception prints crashed" do
      out =
        fire([:git_hoox, :stage, :exception], %{duration: native_ms(5)}, %{
          stage: :pre_commit,
          entries: 1,
          files: 1,
          kind: :error,
          reason: :boom,
          stacktrace: []
        })

      assert out == "✗ pre-commit · crashed\n"
    end
  end

  describe "hook lines" do
    setup do
      Reporter.attach(color: false)
      :ok
    end

    test "start prints running marker with short module name" do
      out =
        fire([:git_hoox, :hook, :start], %{system_time: 0}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Format,
          files: 2
        })

      assert out == "  ▸ Format\n"
    end

    test "stop ok prints green tick and duration" do
      out =
        fire([:git_hoox, :hook, :stop], %{duration: native_ms(38)}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Format,
          files: 2,
          result: :ok,
          error: nil
        })

      assert out == "  ✓ Format · 38ms\n"
    end

    test "stop error with {code, out} prints exit code" do
      out =
        fire([:git_hoox, :hook, :stop], %{duration: native_ms(1400)}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Credo,
          files: 2,
          result: :error,
          error: {1, "some output"}
        })

      assert out == "  ✗ Credo · exit 1 · 1.4s\n"
    end

    test "stop error with an arbitrary reason inspects it" do
      out =
        fire([:git_hoox, :hook, :stop], %{duration: native_ms(10)}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Format,
          files: 2,
          result: :error,
          error: :boom
        })

      assert out == "  ✗ Format · :boom · 10ms\n"
    end

    test "stop skip prints dimmed skip line" do
      out =
        fire([:git_hoox, :hook, :stop], %{duration: native_ms(1)}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Test,
          files: 0,
          result: :skip,
          error: nil
        })

      assert out == "  - Test · skipped (no matched files)\n"
    end

    test "skip event prints dimmed skip line" do
      out =
        fire([:git_hoox, :hook, :skip], %{system_time: 0}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Test,
          files: 0
        })

      assert out == "  - Test · skipped (no matched files)\n"
    end

    test "timeout exception prints timeout" do
      out =
        fire([:git_hoox, :hook, :exception], %{duration: native_ms(30_000)}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Test,
          files: 2,
          kind: :exit,
          reason: {:git_hoox_timeout, 30_000},
          stacktrace: []
        })

      assert out == "  ✗ Test · timeout after 30000ms\n"
    end

    test "crash exception prints crashed with kind and reason" do
      out =
        fire([:git_hoox, :hook, :exception], %{duration: native_ms(5)}, %{
          stage: :pre_commit,
          module: GitHoox.Hooks.Format,
          files: 2,
          kind: :error,
          reason: %RuntimeError{message: "boom"},
          stacktrace: []
        })

      assert String.starts_with?(out, "  ✗ Format · crashed · error: ")
      assert out =~ "boom"
    end

    test "custom hook keeps its full module name" do
      out =
        fire([:git_hoox, :hook, :stop], %{duration: native_ms(5)}, %{
          stage: :pre_commit,
          module: MyApp.Hooks.Coverage,
          files: 2,
          result: :ok,
          error: nil
        })

      assert out == "  ✓ MyApp.Hooks.Coverage · 5ms\n"
    end
  end

  describe "colour toggle" do
    @start_event [:git_hoox, :stage, :start]
    @start_meta %{stage: :pre_commit, entries: 1, files: 1}

    test "color: true emits ANSI escapes" do
      Reporter.attach(color: true)
      out = fire(@start_event, %{system_time: 0}, @start_meta)
      assert out =~ "\e["
      assert out =~ "→"
    end

    test "color: false strips ANSI escapes" do
      Reporter.attach(color: false)
      out = fire(@start_event, %{system_time: 0}, @start_meta)
      refute out =~ "\e["
      assert out =~ "→ pre-commit"
    end
  end

  describe "colour never leaks past a line" do
    setup do
      Reporter.attach(color: true)
      :ok
    end

    # Every event that produces coloured output. IO.ANSI.format/2 appends
    # a trailing reset automatically, but pin it: a future switch to
    # format_fragment/2 or hand-rolled escapes would drop the reset and
    # leak the last style into the user's shell prompt.
    @leak_cases [
      {[:git_hoox, :stage, :start], %{system_time: 0}, %{stage: :pre_commit, entries: 3, files: 5}},
      {[:git_hoox, :stage, :stop], %{duration: 1_000_000},
       %{stage: :pre_commit, entries: 3, files: 5, result: :ok, failures: 0}},
      {[:git_hoox, :stage, :stop], %{duration: 1_000_000},
       %{stage: :pre_commit, entries: 3, files: 5, result: :error, failures: 1}},
      {[:git_hoox, :stage, :exception], %{duration: 1_000_000},
       %{stage: :pre_commit, entries: 1, files: 1, kind: :error, reason: :boom, stacktrace: []}},
      {[:git_hoox, :hook, :start], %{system_time: 0},
       %{stage: :pre_commit, module: GitHoox.Hooks.Format, files: 2}},
      {[:git_hoox, :hook, :stop], %{duration: 1_000_000},
       %{stage: :pre_commit, module: GitHoox.Hooks.Format, files: 2, result: :ok, error: nil}},
      {[:git_hoox, :hook, :stop], %{duration: 1_000_000},
       %{
         stage: :pre_commit,
         module: GitHoox.Hooks.Credo,
         files: 2,
         result: :error,
         error: {1, "out"}
       }},
      {[:git_hoox, :hook, :stop], %{duration: 1_000_000},
       %{stage: :pre_commit, module: GitHoox.Hooks.Format, files: 2, result: :error, error: :boom}},
      {[:git_hoox, :hook, :stop], %{duration: 1_000_000},
       %{stage: :pre_commit, module: GitHoox.Hooks.Test, files: 0, result: :skip, error: nil}},
      {[:git_hoox, :hook, :skip], %{system_time: 0},
       %{stage: :pre_commit, module: GitHoox.Hooks.Test, files: 0}},
      {[:git_hoox, :hook, :exception], %{duration: 1_000_000},
       %{
         stage: :pre_commit,
         module: GitHoox.Hooks.Test,
         files: 2,
         kind: :exit,
         reason: {:git_hoox_timeout, 30_000},
         stacktrace: []
       }},
      {[:git_hoox, :hook, :exception], %{duration: 1_000_000},
       %{
         stage: :pre_commit,
         module: GitHoox.Hooks.Format,
         files: 2,
         kind: :error,
         reason: %RuntimeError{message: "boom"},
         stacktrace: []
       }}
    ]

    test "every coloured line ends with a reset" do
      reset = IO.ANSI.reset()

      for {event, measurements, meta} <- @leak_cases do
        line = fire(event, measurements, meta) |> String.trim_trailing("\n")

        assert String.contains?(line, "\e["),
               "expected colour codes for #{inspect(event)}"

        assert String.ends_with?(line, reset),
               "colour leaked (no trailing reset) for #{inspect(event)}: #{inspect(line)}"
      end
    end
  end

  describe "colour policy" do
    @color_vars ~w(GIT_HOOX_COLOR NO_COLOR CLICOLOR_FORCE FORCE_COLOR)
    @start_event [:git_hoox, :stage, :start]
    @start_meta %{stage: :pre_commit, entries: 1, files: 1}

    setup do
      saved = Map.new(@color_vars, fn k -> {k, System.get_env(k)} end)

      on_exit(fn ->
        Enum.each(saved, fn
          {k, nil} -> System.delete_env(k)
          {k, v} -> System.put_env(k, v)
        end)
      end)

      :ok
    end

    defp set_env(kvs) do
      Enum.each(@color_vars, &System.delete_env/1)
      Enum.each(kvs, fn {k, v} -> System.put_env(k, v) end)
    end

    defp ansi?(out), do: String.contains?(out, "\e[")

    test "GIT_HOOX_COLOR=always wins over NO_COLOR" do
      set_env([{"GIT_HOOX_COLOR", "always"}, {"NO_COLOR", "1"}])
      Reporter.attach()
      assert ansi?(fire(@start_event, %{system_time: 0}, @start_meta))
    end

    test "GIT_HOOX_COLOR=never wins over FORCE_COLOR" do
      set_env([{"GIT_HOOX_COLOR", "never"}, {"FORCE_COLOR", "1"}])
      Reporter.attach()
      refute ansi?(fire(@start_event, %{system_time: 0}, @start_meta))
    end

    test "NO_COLOR wins over CLICOLOR_FORCE" do
      set_env([{"NO_COLOR", "1"}, {"CLICOLOR_FORCE", "1"}])
      Reporter.attach()
      refute ansi?(fire(@start_event, %{system_time: 0}, @start_meta))
    end

    test "FORCE_COLOR turns colour on" do
      set_env([{"FORCE_COLOR", "1"}])
      Reporter.attach()
      assert ansi?(fire(@start_event, %{system_time: 0}, @start_meta))
    end

    test "CLICOLOR_FORCE=0 is not a force, falls through to FORCE_COLOR" do
      set_env([{"CLICOLOR_FORCE", "0"}, {"FORCE_COLOR", "1"}])
      Reporter.attach()
      assert ansi?(fire(@start_event, %{system_time: 0}, @start_meta))
    end
  end

  describe "robustness" do
    test "a known event with an unexpected shape neither prints nor detaches" do
      Reporter.attach(color: false)

      out =
        fire([:git_hoox, :hook, :stop], %{duration: 1}, %{
          module: GitHoox.Hooks.Format,
          result: :weird
        })

      assert out == ""

      assert Enum.any?(
               :telemetry.list_handlers([:git_hoox, :hook, :stop]),
               &(&1.id == "git_hoox.reporter")
             )
    end
  end

  describe "attach / detach" do
    test "attach twice returns already_exists" do
      assert :ok = Reporter.attach(color: false)
      assert {:error, :already_exists} = Reporter.attach(color: false)
    end

    test "detach is idempotent" do
      Reporter.attach(color: false)
      assert :ok = Reporter.detach()
      assert {:error, :not_found} = Reporter.detach()
    end
  end

  describe "integration" do
    setup %{repo: dir} do
      Reporter.attach(color: false)
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])
      :ok
    end

    test "serial run prints header, per-hook lines and summary", %{repo: dir} do
      write_config(dir, """
      %{
        hooks: [pre_commit: [
          {GitHoox.TestHooks.Pass, []},
          {GitHoox.TestHooks.Fail, [reason: "nope"]}
        ]],
        parallel: false
      }
      """)

      out =
        capture_io(fn ->
          in_repo(dir, fn -> assert {:error, _} = Runner.run(:pre_commit) end)
        end)

      assert out =~ "→ pre-commit · 2 hooks · 1 file"
      assert out =~ "  ▸ GitHoox.TestHooks.Pass"
      assert out =~ "  ✓ GitHoox.TestHooks.Pass"
      assert out =~ "  ✗ GitHoox.TestHooks.Fail · \"nope\""
      assert out =~ "✗ pre-commit · 1/2 failed"
    end

    test "parallel run keeps each hook's start/stop lines contiguous", %{repo: dir} do
      write_config(dir, """
      %{
        hooks: [pre_commit: [
          {GitHoox.TestHooks.Pass, []},
          {GitHoox.TestHooks.Fail, [reason: "nope"]}
        ]],
        parallel: true
      }
      """)

      out =
        capture_io(fn ->
          in_repo(dir, fn -> assert {:error, _} = Runner.run(:pre_commit) end)
        end)

      lines = String.split(out, "\n", trim: true)

      assert_contiguous(lines, "GitHoox.TestHooks.Pass")
      assert_contiguous(lines, "GitHoox.TestHooks.Fail")
    end

    # A hook's ▸ start line must be immediately followed by its own
    # terminal (✓/✗) line — the per-task capture buffer flushes them as
    # one block, so no other hook's line lands between them.
    defp assert_contiguous(lines, mod) do
      start_idx = Enum.find_index(lines, &String.contains?(&1, "▸ #{mod}"))
      stop_idx = Enum.find_index(lines, &(&1 =~ ~r/[✓✗] #{Regex.escape(mod)}/))

      assert start_idx, "no start line for #{mod} in:\n#{Enum.join(lines, "\n")}"
      assert stop_idx, "no stop line for #{mod} in:\n#{Enum.join(lines, "\n")}"

      assert stop_idx == start_idx + 1,
             "expected #{mod} start/stop contiguous, got #{start_idx}/#{stop_idx} in:\n#{Enum.join(lines, "\n")}"
    end
  end

  describe "mix task wiring" do
    setup %{repo: dir} do
      on_exit(fn ->
        Application.put_env(:git_hoox, :reporter, false)
        Reporter.detach()
      end)

      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      write_config(dir, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
      """)

      :ok
    end

    defp attached? do
      Enum.any?(
        :telemetry.list_handlers([:git_hoox, :stage, :start]),
        &(&1.id == "git_hoox.reporter")
      )
    end

    test "reporter: true attaches the handler and prints status", %{repo: dir} do
      Application.put_env(:git_hoox, :reporter, true)

      out =
        capture_io(fn ->
          in_repo(dir, fn -> RunTask.run(["pre-commit"]) end)
        end)

      # Substring survives colour: the hook line is a single dimmed
      # segment, unlike the stage line which colour splits mid-string.
      assert out =~ "▸ GitHoox.TestHooks.Pass"
      assert attached?()
    end

    test "reporter: false leaves the handler unattached and silent", %{repo: dir} do
      Application.put_env(:git_hoox, :reporter, false)

      out =
        capture_io(fn ->
          in_repo(dir, fn -> RunTask.run(["pre-commit"]) end)
        end)

      refute out =~ "▸"
      refute attached?()
    end
  end
end
