defmodule MyApp.Hooks.JiraTicket do
  @moduledoc """
  Reject `commit_msg` files that do not contain a JIRA-style ticket ref.

  The `:prefix` option sets the project key; `:pattern` overrides the
  matched regex entirely if you need something more elaborate.

  Example registration:

      commit_msg: [
        {MyApp.Hooks.JiraTicket, prefix: "PROJ-"}
      ]

  Commits like `merge branch …` are common and rarely carry a ticket. They
  are skipped by default — override with `:skip_merge_commits` if you need
  to enforce there too.
  """

  @behaviour GitHoox.Hook

  @impl true
  def default_opts do
    [files: ["**/*"], prefix: "PROJ-", skip_merge_commits: true]
  end

  @impl true
  def run([msg_path], opts) do
    case File.read(msg_path) do
      {:ok, content} -> validate(content, opts)
      {:error, reason} -> {:error, "could not read #{msg_path}: #{inspect(reason)}"}
    end
  end

  def run(_files, _opts), do: :ok

  defp validate(content, opts) do
    if merge_commit?(content) and Keyword.get(opts, :skip_merge_commits, true) do
      :ok
    else
      regex = build_regex(opts)

      if Regex.match?(regex, content) do
        :ok
      else
        {:error, "commit message missing ticket reference (expected #{inspect(regex)})"}
      end
    end
  end

  defp merge_commit?(content) do
    String.starts_with?(content, "Merge ")
  end

  defp build_regex(opts) do
    case Keyword.get(opts, :pattern) do
      %Regex{} = r -> r
      nil -> Regex.compile!(Regex.escape(Keyword.fetch!(opts, :prefix)) <> "\\d+")
    end
  end
end
