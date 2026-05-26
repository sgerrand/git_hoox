defmodule GitHoox.BenchTest do
  use ExUnit.Case, async: true

  alias GitHoox.Bench

  describe "summarize/1" do
    test "empty input returns an empty list" do
      assert [] = Bench.summarize(%{})
    end

    test "computes percentiles from native time samples" do
      # Convert milliseconds to native units so we exercise the same path
      # Runner uses.
      ms = fn n -> System.convert_time_unit(n, :millisecond, :native) end
      samples = %{ModA => {Enum.map([10, 20, 30, 40, 50], ms), 0}}

      [summary] = Bench.summarize(samples)
      assert summary.module == ModA
      assert summary.runs == 5
      assert summary.errors == 0
      assert summary.p50_ms == 30
      assert summary.p95_ms == 50
      assert summary.max_ms == 50
      assert summary.mean_ms == 30.0
      assert summary.total_ms == 150
    end

    test "sorts results by total descending" do
      ms = fn n -> System.convert_time_unit(n, :millisecond, :native) end

      samples = %{
        Fast => {Enum.map([1, 1, 1], ms), 0},
        Slow => {Enum.map([100, 100], ms), 0},
        Mid => {Enum.map([10, 10, 10], ms), 0}
      }

      modules = Bench.summarize(samples) |> Enum.map(& &1.module)
      assert modules == [Slow, Mid, Fast]
    end

    test "carries the error count through" do
      ms = fn n -> System.convert_time_unit(n, :millisecond, :native) end
      samples = %{Crashy => {[ms.(50)], 1}}

      [summary] = Bench.summarize(samples)
      assert summary.errors == 1
      assert summary.runs == 1
    end

    test "module with no samples reports zeroed percentiles" do
      assert [s] = Bench.summarize(%{ModX => {[], 0}})
      assert s.p50_ms == 0
      assert s.p95_ms == 0
      assert s.max_ms == 0
      assert s.mean_ms == 0
    end
  end
end
