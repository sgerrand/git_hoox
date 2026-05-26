Application.put_env(:git_hoox, :stream_output, false)
ExUnit.start(exclude: [:slow, :network])
