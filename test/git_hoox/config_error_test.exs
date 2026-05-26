defmodule GitHoox.Config.ErrorTest do
  use ExUnit.Case, async: true

  alias GitHoox.Config.Error, as: ConfigError

  test "missing_config mentions install command" do
    msg = ConfigError.format({:missing_config, ".git_hoox.exs"})
    assert msg =~ "Config not found"
    assert msg =~ "mix git_hoox.install"
  end

  test "invalid_config wraps the underlying message" do
    msg = ConfigError.format({:invalid_config, "missing :hooks"})
    assert msg =~ "Invalid .git_hoox.exs"
    assert msg =~ "missing :hooks"
  end

  test "invalid_stages renders bad + valid lists" do
    msg = ConfigError.format({:invalid_stages, [:bogus], [:pre_commit, :pre_push]})
    assert msg =~ "Unknown git stages"
    assert msg =~ "bogus"
    assert msg =~ "pre_commit"
  end

  test "invalid_hook_entry shows the offending value" do
    msg = ConfigError.format({:invalid_hook_entry, :pre_commit, "junk"})
    assert msg =~ "Invalid hook entry"
    assert msg =~ "pre_commit"
    assert msg =~ "junk"
  end

  test "invalid_hook_module renders module + reason" do
    msg = ConfigError.format({:invalid_hook_module, :pre_commit, NotAMod, "not loaded"})
    assert msg =~ "Invalid hook module"
    assert msg =~ "NotAMod"
    assert msg =~ "not loaded"
  end

  test "invalid_hook_opts shows the underlying schema error" do
    msg = ConfigError.format({:invalid_hook_opts, :pre_commit, SomeMod, "bad opt"})
    assert msg =~ "Invalid opts"
    assert msg =~ "SomeMod"
    assert msg =~ "bad opt"
  end
end
