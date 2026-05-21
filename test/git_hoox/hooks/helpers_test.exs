defmodule GitHoox.Hooks.HelpersTest do
  use ExUnit.Case, async: true

  alias GitHoox.Hooks.Helpers

  test "env_opt returns [] when :env is missing" do
    assert Helpers.env_opt([]) == []
  end

  test "env_opt returns [] when :env is empty map" do
    assert Helpers.env_opt(env: %{}) == []
  end

  test "env_opt converts string-keyed map to keyword-style list" do
    pairs = Helpers.env_opt(env: %{"FOO" => "1", "BAR" => "two"})
    assert Enum.sort(pairs) == [{"BAR", "two"}, {"FOO", "1"}]
  end
end
