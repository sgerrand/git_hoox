defmodule GitHoox.Hooks.ShellTest do
  use GitHoox.Case, async: false

  alias GitHoox.Hooks.Shell

  defp in_repo(dir, fun), do: File.cd!(dir, fun)

  describe "empty file handling" do
    test "skips when {files} is in template and files == []", %{repo: dir} do
      in_repo(dir, fn ->
        assert :ok = Shell.run([], run: "touch ran && false {files}")
        refute File.exists?("ran"), "command should not have run"
      end)
    end

    test "skips when {staged_files} is referenced and nothing is staged", %{repo: dir} do
      in_repo(dir, fn ->
        assert :ok = Shell.run([], run: "touch ran && false {staged_files}")
        refute File.exists?("ran")
      end)
    end

    test "runs normally when template has no file tokens", %{repo: dir} do
      in_repo(dir, fn ->
        assert :ok = Shell.run([], run: "true")
      end)
    end

    test "runs when files is non-empty and template uses {files}", %{repo: dir} do
      write(dir, "marker.txt", "x")

      in_repo(dir, fn ->
        assert :ok = Shell.run(["marker.txt"], run: "test -f {files}")
      end)
    end
  end

  describe "token substitution" do
    test "{files} expands from the hook arg", %{repo: dir} do
      write(dir, "a.txt", "x")
      write(dir, "b.txt", "y")

      in_repo(dir, fn ->
        assert :ok =
                 Shell.run(["a.txt", "b.txt"],
                   run: "test -f a.txt && test -f b.txt && echo {files} > out"
                 )

        assert File.read!("out") =~ "a.txt"
        assert File.read!("out") =~ "b.txt"
      end)
    end

    test "{staged_files} reads from git diff --cached, not from the hook arg", %{repo: dir} do
      write(dir, "lib/foo.ex", "x\n")
      stage(dir, ["lib/foo.ex"])

      in_repo(dir, fn ->
        opts = [run: "echo {staged_files} > out"]
        assert :ok = Shell.run(["unrelated.txt"], opts)
        assert File.read!("out") =~ "lib/foo.ex"
      end)
    end

    test "{all_files} reads from git ls-files", %{repo: dir} do
      in_repo(dir, fn ->
        assert :ok = Shell.run([], run: "echo {all_files} > out && true")
        assert File.read!("out") =~ "README.md"
      end)
    end

    test "paths with spaces are shell-escaped", %{repo: dir} do
      write(dir, "lib/has space.txt", "x")
      stage(dir, ["lib/has space.txt"])

      in_repo(dir, fn ->
        assert :ok = Shell.run(["lib/has space.txt"], run: "test -f {files}")
      end)
    end
  end

  describe "errors" do
    test "missing :run returns an error" do
      assert {:error, msg} = Shell.run(["x"], [])
      assert msg =~ ":run"
    end

    test "non-zero exit propagates", %{repo: dir} do
      in_repo(dir, fn ->
        assert {:error, {1, _}} = Shell.run(["x"], run: "exit 1")
      end)
    end
  end
end
