defmodule GitHoox.TestHooks do
  @moduledoc false

  defmodule Pass do
    @moduledoc false
    @behaviour GitHoox.Hook

    @impl true
    def default_opts, do: [files: ["**/*"]]

    @impl true
    def run(_files, _opts), do: :ok
  end

  defmodule Fail do
    @moduledoc false
    @behaviour GitHoox.Hook

    @impl true
    def default_opts, do: [files: ["**/*"]]

    @impl true
    def run(_files, opts) do
      {:error, Keyword.get(opts, :reason, "boom")}
    end
  end

  defmodule MutateAndReport do
    @moduledoc false
    @behaviour GitHoox.Hook

    @impl true
    def default_opts, do: [files: ["**/*"], stage_fixed: true]

    @impl true
    def run(files, _opts) do
      Enum.each(files, fn f -> File.write!(f, "mutated\n") end)
      {:ok, files}
    end
  end

  defmodule Counter do
    @moduledoc false
    @behaviour GitHoox.Hook

    def start_link, do: Agent.start_link(fn -> 0 end, name: __MODULE__)
    def count, do: Agent.get(__MODULE__, & &1)
    def reset, do: if(Process.whereis(__MODULE__), do: Agent.update(__MODULE__, fn _ -> 0 end))

    @impl true
    def default_opts, do: [files: ["**/*"]]

    @impl true
    def run(_files, _opts) do
      Agent.update(__MODULE__, &(&1 + 1))
      :ok
    end
  end
end
