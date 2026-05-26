defmodule GitHoox.ConfigOptsSchemaTest do
  use ExUnit.Case, async: true

  alias GitHoox.Config

  setup do
    tmp = Path.join(System.tmp_dir!(), "git_hoox_optsch_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, tmp: tmp}
  end

  defp write_config(tmp, body) do
    path = Path.join(tmp, ".git_hoox.exs")
    File.write!(path, body)
    path
  end

  describe "built-in hook schemas" do
    test "Format rejects unknown opt", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.Hooks.Format, [check_olny: true]}]]}
        """)

      assert {:error, {:invalid_hook_opts, :pre_commit, GitHoox.Hooks.Format, msg}} =
               Config.load(path)

      assert msg =~ "check_olny"
    end

    test "Format accepts valid :check_only", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.Hooks.Format, [check_only: true]}]]}
        """)

      assert {:ok, _} = Config.load(path)
    end

    test "Credo rejects non-boolean :strict", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.Hooks.Credo, [strict: "yes"]}]]}
        """)

      assert {:error, {:invalid_hook_opts, :pre_commit, GitHoox.Hooks.Credo, msg}} =
               Config.load(path)

      assert msg =~ "strict"
    end

    test "Test rejects invalid :scope value", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_push: [{GitHoox.Hooks.Test, [scope: :nope]}]]}
        """)

      assert {:error, {:invalid_hook_opts, :pre_push, GitHoox.Hooks.Test, msg}} =
               Config.load(path)

      assert msg =~ "scope"
    end

    test "Test accepts :scope from the enum", %{tmp: tmp} do
      for scope <- [:all, :stale, :related] do
        path =
          write_config(tmp, """
          %{hooks: [pre_push: [{GitHoox.Hooks.Test, [scope: #{inspect(scope)}]}]]}
          """)

        assert {:ok, _} = Config.load(path)
      end
    end

    test "Shell rejects entry missing required :run", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.Hooks.Shell, []}]]}
        """)

      assert {:error, {:invalid_hook_opts, :pre_commit, GitHoox.Hooks.Shell, msg}} =
               Config.load(path)

      assert msg =~ "run"
    end

    test "Shell accepts :run with default :shell", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.Hooks.Shell, [run: "echo hi"]}]]}
        """)

      assert {:ok, _} = Config.load(path)
    end

    test "Dialyzer rejects unknown opt despite empty schema", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_push: [{GitHoox.Hooks.Dialyzer, [whatever: 1]}]]}
        """)

      assert {:error, {:invalid_hook_opts, :pre_push, GitHoox.Hooks.Dialyzer, msg}} =
               Config.load(path)

      assert msg =~ "whatever"
    end
  end

  describe "hooks without opts_schema" do
    test "TestHooks.Fail still accepts arbitrary :reason opt", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.TestHooks.Fail, [reason: "boom"]}]]}
        """)

      assert {:ok, _} = Config.load(path)
    end

    test "TestHooks.Slow still accepts arbitrary :sleep_ms opt", %{tmp: tmp} do
      path =
        write_config(tmp, """
        %{hooks: [pre_commit: [{GitHoox.TestHooks.Slow, [sleep_ms: 50]}]]}
        """)

      assert {:ok, _} = Config.load(path)
    end
  end
end
