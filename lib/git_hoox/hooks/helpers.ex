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

  @doc """
  Run `command` via `GitHoox.Cmd.run/3` with the hook's `:env` option
  applied. Single enforcement point for `:env` across built-in hooks.
  """
  @spec cmd(String.t(), [String.t()], keyword()) :: {String.t(), non_neg_integer()}
  def cmd(command, args, opts) do
    GitHoox.Cmd.run(command, args, env: env_opt(opts))
  end

  @doc "Run `mix` with `args` and map the result into the hook contract."
  @spec mix([String.t()], keyword()) :: :ok | {:error, {non_neg_integer(), String.t()}}
  def mix(args, opts) do
    "mix" |> cmd(args, opts) |> to_result()
  end

  @doc """
  NimbleOptions entry for the `:args` option shared by every hook that
  shells out to a command. Only the doc string differs per hook.
  """
  @spec args_schema(String.t()) :: keyword()
  def args_schema(doc), do: [type: {:list, :string}, default: [], doc: doc]
end
