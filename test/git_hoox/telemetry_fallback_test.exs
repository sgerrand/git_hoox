defmodule GitHoox.TelemetryFallbackTest do
  use ExUnit.Case, async: true

  alias GitHoox.Telemetry

  test "stage_span treats non-:ok / non-error-list returns as error with 1 failure" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:git_hoox, :stage, :stop]])
    on_exit(fn -> :telemetry.detach(ref) end)

    Telemetry.stage_span(:custom, 0, 0, fn -> :weird_return end)

    assert_receive {[:git_hoox, :stage, :stop], ^ref, _, %{result: :error, failures: 1}}
  end

  test "hook_span :skip result reports result: :skip" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:git_hoox, :hook, :stop]])
    on_exit(fn -> :telemetry.detach(ref) end)

    Telemetry.hook_span(:pre_commit, SomeMod, 0, fn -> :skip end)

    assert_receive {[:git_hoox, :hook, :stop], ^ref, _, %{result: :skip}}
  end

  test "hook_span {:ok, modified} reports result: :ok" do
    ref = :telemetry_test.attach_event_handlers(self(), [[:git_hoox, :hook, :stop]])
    on_exit(fn -> :telemetry.detach(ref) end)

    Telemetry.hook_span(:pre_commit, SomeMod, 1, fn -> {:ok, ["lib/x.ex"]} end)

    assert_receive {[:git_hoox, :hook, :stop], ^ref, _, %{result: :ok, error: nil}}
  end
end
