defmodule MyApp.Hooks.Coverage do
  @moduledoc """
  Run `mix coveralls` on `pre_push` and fail when total coverage drops below
  the configured threshold.

  Requires [excoveralls](https://hex.pm/packages/excoveralls):

      {:excoveralls, "~> 0.18", only: :test}

  And in `mix.exs`:

      def project do
        [
          # ...
          test_coverage: [tool: ExCoveralls]
        ]
      end

  Example registration:

      pre_push: [
        {MyApp.Hooks.Coverage, threshold: 80}
      ]
  """

  @behaviour GitHoox.Hook

  @impl true
  def default_opts do
    [files: ~w(lib/**/*.ex test/**/*.exs), threshold: 80]
  end

  @impl true
  def run(_files, opts) do
    threshold = Keyword.fetch!(opts, :threshold)

    case System.cmd("mix", ["coveralls"], stderr_to_stdout: true) do
      {out, 0} ->
        case parse_total(out) do
          {:ok, total} when total >= threshold ->
            :ok

          {:ok, total} ->
            {:error, "coverage #{total}% < threshold #{threshold}%\n#{out}"}

          :error ->
            {:error, "could not parse coveralls output:\n#{out}"}
        end

      {out, code} ->
        {:error, {code, out}}
    end
  end

  defp parse_total(out) do
    case Regex.run(~r/\[TOTAL\]\s+([\d.]+)%/, out) do
      [_, pct] ->
        case Float.parse(pct) do
          {f, _} -> {:ok, f}
          :error -> :error
        end

      _ ->
        :error
    end
  end
end
