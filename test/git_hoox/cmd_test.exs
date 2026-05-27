defmodule GitHoox.CmdTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO

  alias GitHoox.Cmd

  describe "return value" do
    test "captures stdout and reports exit 0 on success" do
      {out, status} = Cmd.run("sh", ["-c", "echo hello"], stream: false)
      assert status == 0
      assert out =~ "hello"
    end

    test "captures combined stdout/stderr" do
      {out, 0} = Cmd.run("sh", ["-c", "echo out; echo err 1>&2"], stream: false)
      assert out =~ "out"
      assert out =~ "err"
    end

    test "propagates non-zero exit status" do
      {_out, status} = Cmd.run("sh", ["-c", "exit 7"], stream: false)
      assert status == 7
    end
  end

  describe "streaming" do
    test "writes chunks to the device as they arrive when stream: true" do
      out =
        capture_io(fn ->
          {_, 0} = Cmd.run("sh", ["-c", "echo streamed-line"], stream: true)
        end)

      assert out =~ "streamed-line"
    end

    test "stream: false stays silent" do
      out =
        capture_io(fn ->
          {_, 0} = Cmd.run("sh", ["-c", "echo not-streamed"], stream: false)
        end)

      refute out =~ "not-streamed"
    end

    test "default falls back to Application env" do
      original = Application.get_env(:git_hoox, :stream_output)
      Application.put_env(:git_hoox, :stream_output, true)

      out =
        try do
          capture_io(fn ->
            {_, 0} = Cmd.run("sh", ["-c", "echo via-app-env"])
          end)
        after
          Application.put_env(:git_hoox, :stream_output, original)
        end

      assert out =~ "via-app-env"
    end
  end

  describe "env" do
    test "passes env vars to the child process" do
      {out, 0} =
        Cmd.run("sh", ["-c", "printf %s \"$GIT_HOOX_TEST\""],
          env: [{"GIT_HOOX_TEST", "marker-value"}],
          stream: false
        )

      assert out == "marker-value"
    end
  end

  describe "errors" do
    test "returns 127 with a message when executable cannot be resolved" do
      missing = "definitely-not-a-real-binary-#{System.unique_integer([:positive])}"
      assert {out, 127} = Cmd.run(missing, [], stream: false)
      assert out =~ "executable not found"
      assert out =~ missing
    end
  end
end
