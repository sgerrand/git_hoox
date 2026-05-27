defmodule GitHoox.Hooks.Helpers do
  @moduledoc false

  @doc """
  Convert the `:env` option (a map of `String.t() => String.t()`) into the
  list shape that `System.cmd/3` expects.
  """
  @spec env_opt(keyword()) :: [{String.t(), String.t()}]
  def env_opt(opts) do
    case Keyword.get(opts, :env) do
      nil -> []
      map when is_map(map) -> Map.to_list(map)
    end
  end

  @doc """
  Map a `{output, exit_status}` tuple from `GitHoox.Cmd.run/3` into the
  hook result contract: `:ok` on exit 0, `{:error, {code, out}}` otherwise.
  """
  @spec to_result({String.t(), non_neg_integer()}) ::
          :ok | {:error, {non_neg_integer(), String.t()}}
  def to_result({_, 0}), do: :ok
  def to_result({out, code}), do: {:error, {code, out}}
end
