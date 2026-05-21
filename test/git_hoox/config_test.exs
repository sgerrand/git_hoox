defmodule GitHoox.ConfigTest do
  use ExUnit.Case, async: true

  alias GitHoox.Config

  setup do
    tmp = Path.join(System.tmp_dir!(), "git_hoox_cfg_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp write_config(tmp, body) do
    path = Path.join(tmp, ".git_hoox.exs")
    File.write!(path, body)
    path
  end

  test "missing file returns :missing_config", %{tmp: tmp} do
    path = Path.join(tmp, "nope.exs")
    assert {:error, {:missing_config, ^path}} = Config.load(path)
  end

  test "minimal valid config loads", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, []}]]}
      """)

    assert {:ok, config} = Config.load(path)
    assert config.parallel == false
    assert config.fail_fast == false
    assert config.skip_env == "GIT_HOOX"
    assert [pre_commit: [{GitHoox.TestHooks.Pass, []}]] = config.hooks
  end

  test "overrides apply", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{
        hooks: [pre_commit: []],
        parallel: true,
        fail_fast: true,
        skip_env: "MY_HOOX"
      }
      """)

    assert {:ok, config} = Config.load(path)
    assert config.parallel == true
    assert config.fail_fast == true
    assert config.skip_env == "MY_HOOX"
  end

  test "invalid stage atom rejected", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [bogus_stage: [{GitHoox.TestHooks.Pass, []}]]}
      """)

    assert {:error, {:invalid_stages, [:bogus_stage], valid}} = Config.load(path)
    assert :pre_commit in valid
  end

  test "non-tuple hook entry rejected", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [pre_commit: ["just a string"]]}
      """)

    assert {:error, {:invalid_hook_entry, :pre_commit, "just a string"}} = Config.load(path)
  end

  test "unloaded hook module rejected", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [pre_commit: [{NotAModule.AtAll, []}]]}
      """)

    assert {:error, {:invalid_hook_module, :pre_commit, NotAModule.AtAll, _}} = Config.load(path)
  end

  test "module without run/2 rejected", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [pre_commit: [{Enum, []}]]}
      """)

    assert {:error, {:invalid_hook_module, :pre_commit, Enum, msg}} = Config.load(path)
    assert msg =~ "run/2"
  end

  test "invalid opts surface as :invalid_hook_opts", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [pre_commit: [{GitHoox.TestHooks.Pass, [timeout: -5]}]]}
      """)

    assert {:error, {:invalid_hook_opts, :pre_commit, GitHoox.TestHooks.Pass, msg}} =
             Config.load(path)

    assert msg =~ "timeout"
  end

  test "top-level extra keys rejected", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{hooks: [pre_commit: []], bogus: true}
      """)

    assert {:error, {:invalid_config, _}} = Config.load(path)
  end

  test "missing :hooks key rejected", %{tmp: tmp} do
    path =
      write_config(tmp, """
      %{parallel: true}
      """)

    assert {:error, {:invalid_config, msg}} = Config.load(path)
    assert msg =~ "hooks"
  end
end
