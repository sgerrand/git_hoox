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
end
