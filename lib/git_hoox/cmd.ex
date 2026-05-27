defmodule GitHoox.Cmd do
  @moduledoc """
  Drop-in replacement for `System.cmd/3` that streams the spawned process's
  combined stdout/stderr to `:stdio` as each chunk arrives, while still
  accumulating the full output for the caller.

  Return shape matches `System.cmd/3` — `{output, exit_status}` — so call
  sites can keep using the existing `{out, 0}` / `{out, code}` patterns.

  ## Options

    * `:env` — env vars as a list of `{key, value}` string tuples, same as
      `System.cmd/3`.
    * `:stream` — explicit override of the streaming behaviour. When
      omitted, falls back to `Application.get_env(:git_hoox, :stream_output, true)`.
      Tests set the application env to `false` in `test/test_helper.exs`
      so they keep clean output; real `mix git_hoox.run` invocations
      stream by default.
    * `:device` — IO device to write streamed chunks to. Default
      `:stdio`. Useful for redirecting to `:stderr` or to a captured
      device in tests.

  Hook timeouts are still enforced one layer up by
  `GitHoox.Runner`. When the runner brutally kills the Task that owns the
  port, BEAM closes the port and the OS child process gets SIGTERM.
  """

  @type cmd_opts :: [
          env: [{String.t(), String.t()}],
          stream: boolean(),
          device: IO.device()
        ]

  @doc """
  Run `command` with `args`, returning `{output, exit_status}`.

  If `command` cannot be resolved on `$PATH`, returns
  `{"git_hoox: executable not found: <command>\n", 127}` so callers can
  keep the standard `{out, code}` match shape. 127 is the POSIX
  command-not-found exit code.
  """
  @spec run(String.t(), [String.t()], cmd_opts()) :: {String.t(), non_neg_integer()}
  def run(command, args, opts \\ []) when is_binary(command) and is_list(args) do
    case System.find_executable(command) do
      nil -> not_found(command)
      exe -> spawn_and_collect(exe, args, opts)
    end
  end

  defp not_found(command) do
    {"git_hoox: executable not found: #{command}\n", 127}
  end

  defp spawn_and_collect(exe, args, opts) do
    env =
      opts
      |> Keyword.get(:env, [])
      |> Enum.map(fn {k, v} -> {String.to_charlist(k), String.to_charlist(v)} end)

    stream? = Keyword.get(opts, :stream, default_stream?())
    device = Keyword.get(opts, :device, :stdio)

    port =
      Port.open(
        {:spawn_executable, exe},
        [
          :binary,
          :exit_status,
          :stderr_to_stdout,
          :use_stdio,
          :hide,
          args: args,
          env: env
        ]
      )

    collect(port, [], stream?, device)
  end

  defp collect(port, chunks, stream?, device) do
    receive do
      {^port, {:data, data}} ->
        if stream?, do: IO.write(device, data)
        collect(port, [data | chunks], stream?, device)

      {^port, {:exit_status, status}} ->
        {chunks |> Enum.reverse() |> IO.iodata_to_binary(), status}
    end
  end

  defp default_stream? do
    Application.get_env(:git_hoox, :stream_output, true)
  end
end
