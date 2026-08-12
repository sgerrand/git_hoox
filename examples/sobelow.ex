defmodule MyApp.Hooks.Sobelow do
  @moduledoc """
  Run `mix sobelow` against the project on `pre_commit`.

  Sobelow analyses the whole project; the staged file list is only used to
  decide whether the hook is relevant (skipped when nothing under `lib/`
  changed). Configure `:confidence` to relax the severity gate.

  If you do not need the skip-when-nothing-changed behaviour, no custom
  module is required — `GitHoox.Hooks.Mix` runs any mix task:

      pre_commit: [
        {GitHoox.Hooks.Mix,
         task: "sobelow", args: ["--exit", "Low", "--skip"], files: ~w(lib/**/*.ex)}
      ]

  Add Sobelow to your project's deps if you have not already:

      {:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}

  Example registration:

      pre_commit: [
        {MyApp.Hooks.Sobelow, confidence: "Medium"}
      ]
  """

  @behaviour GitHoox.Hook

  @impl true
  def default_opts do
    [files: ~w(lib/**/*.ex), confidence: "Low"]
  end

  @impl true
  def run([], _opts), do: :ok

  def run(_files, opts) do
    confidence = Keyword.get(opts, :confidence, "Low")
    args = ["sobelow", "--exit", confidence, "--skip"]

    case GitHoox.Cmd.run("mix", args) do
      {_, 0} -> :ok
      {out, code} -> {:error, {code, out}}
    end
  end
end
