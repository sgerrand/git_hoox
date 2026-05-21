defmodule GitHooxTest do
  use ExUnit.Case, async: true

  test "module exposes run/1" do
    Code.ensure_loaded!(GitHoox)
    assert function_exported?(GitHoox, :run, 1)
  end
end
