defmodule GitHoox.Config.Error do
  @moduledoc """
  Structured errors returned by `GitHoox.Config.load/1`.

  Errors are tagged tuples (see `t:t/0`) and can be turned into a
  human-readable string with `format/1`.
  """

  @type t ::
          {:missing_config, Path.t()}
          | {:invalid_config, String.t()}
          | {:invalid_stages, [atom()], [atom()]}
          | {:invalid_hook_entry, GitHoox.stage(), term()}
          | {:invalid_hook_module, GitHoox.stage(), term(), String.t()}
          | {:invalid_hook_opts, GitHoox.stage(), module(), String.t()}

  @spec format(t()) :: String.t()
  def format({:missing_config, path}) do
    "Config not found: #{path}. Run `mix git_hoox.install` to generate."
  end

  def format({:invalid_config, msg}) do
    "Invalid .git_hoox.exs:\n  #{msg}"
  end

  def format({:invalid_stages, bad, valid}) do
    """
    Unknown git stages: #{inspect(bad)}
    Valid: #{inspect(valid)}
    """
  end

  def format({:invalid_hook_entry, stage, entry}) do
    "Invalid hook entry in stage #{stage}: #{inspect(entry)}. Expected `{Module, keyword_opts}`."
  end

  def format({:invalid_hook_module, stage, mod, reason}) do
    "Invalid hook module #{inspect(mod)} in stage #{stage}: #{reason}"
  end

  def format({:invalid_hook_opts, stage, mod, msg}) do
    """
    Invalid opts for #{inspect(mod)} in stage #{stage}:
      #{msg}
    """
  end
end
