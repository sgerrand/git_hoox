defmodule Mix.Tasks.GitHoox.List do
  @shortdoc "Print the resolved hook configuration"

  @moduledoc """
  Show the resolved hook configuration for the current repo.

      mix git_hoox.list

  Loads `.git_hoox.exs`, merges per-hook `default_opts/0` with the user
  options, and prints each stage with its hooks and the opts each hook will
  see at run time. Useful as a debug companion to `mix git_hoox.doctor`.

  Exits non-zero if the config fails to load or validate.
  """

  use Mix.Task

  alias GitHoox.Config
  alias GitHoox.Config.Error, as: ConfigError

  @impl Mix.Task
  @spec run([String.t()]) :: :ok | no_return()
  def run(_argv) do
    case Config.load() do
      {:ok, config} ->
        print(config)
        :ok

      {:error, reason} ->
        Mix.raise(ConfigError.format(reason))
    end
  end

  defp print(config) do
    Mix.shell().info("# git_hoox config")
    Mix.shell().info("")
    Mix.shell().info("parallel:  #{config.parallel}")
    Mix.shell().info("fail_fast: #{config.fail_fast}")
    Mix.shell().info("skip_env:  #{config.skip_env}")
    Mix.shell().info("")

    case config.hooks do
      [] -> Mix.shell().info("(no hooks configured)")
      hooks -> Enum.each(hooks, &print_stage/1)
    end
  end

  defp print_stage({stage, entries}) do
    Mix.shell().info("#{stage}:")

    case entries do
      [] -> Mix.shell().info("  (none)")
      _ -> Enum.each(entries, &print_entry/1)
    end

    Mix.shell().info("")
  end

  defp print_entry({mod, user_opts}) do
    merged = merge(mod, user_opts)
    Mix.shell().info("  #{inspect(mod)}")

    Enum.each(merged, fn {k, v} ->
      Mix.shell().info("    #{k}: #{inspect(v)}")
    end)
  end

  defp merge(mod, user_opts) do
    defaults =
      if function_exported?(mod, :default_opts, 0),
        do: mod.default_opts(),
        else: []

    Keyword.merge(defaults, user_opts)
  end
end
