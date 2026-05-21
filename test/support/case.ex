defmodule GitHoox.Case do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      import GitHoox.GitFixture

      setup do
        dir = init_repo(initial_commit: true)
        on_exit(fn -> File.rm_rf!(dir) end)
        {:ok, repo: dir}
      end
    end
  end
end
