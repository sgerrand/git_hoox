defmodule GitHoox.Hooks.Dialyzer do
  @moduledoc """
  Runs `mix dialyzer --quiet`.

  **Slow** — PLT builds and whole-project analysis make this unsuitable
  for `pre_commit`. Configure on `pre_push`.

  ## Defaults

    * `stage_fixed: false`
    * `files: ~w(lib/**/*.ex)`
  """

  @behaviour GitHoox.Hook

  @impl true
  @spec default_opts() :: keyword()
  def default_opts do
    [stage_fixed: false, files: ~w(lib/**/*.ex)]
  end

  @impl true
  @spec run(GitHoox.Hook.files(), GitHoox.Hook.opts()) :: GitHoox.hook_result()
  def run(_files, _opts) do
    case System.cmd("mix", ["dialyzer", "--quiet"], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, {code, out}}
    end
  end
end
