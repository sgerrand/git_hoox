defmodule GitHoox.LoggerFormatTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  test "long durations format as seconds with two-decimal precision" do
    native = System.convert_time_unit(1500, :millisecond, :native)

    log =
      capture_log(fn ->
        GitHoox.Logger.handle(
          [:git_hoox, :stage, :stop],
          %{duration: native},
          %{stage: :pre_commit, entries: 1, files: 1, result: :ok, failures: 0},
          nil
        )
      end)

    assert log =~ "1.5s"
  end

  test "sub-second durations format as ms" do
    native = System.convert_time_unit(42, :millisecond, :native)

    log =
      capture_log(fn ->
        GitHoox.Logger.handle(
          [:git_hoox, :stage, :stop],
          %{duration: native},
          %{stage: :pre_commit, entries: 1, files: 1, result: :ok, failures: 0},
          nil
        )
      end)

    assert log =~ "42ms"
  end
end
