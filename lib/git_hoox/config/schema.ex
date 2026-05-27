defmodule GitHoox.Config.Schema do
  @moduledoc false

  @stages ~w(pre_commit prepare_commit_msg commit_msg post_commit
             pre_rebase post_checkout post_merge pre_push)a

  @hook_opts_schema [
    files: [
      type: {:list, :string},
      default: ["**/*"],
      doc: "Glob patterns matching files this hook applies to."
    ],
    stage_fixed: [
      type: :boolean,
      doc: "Re-stage files modified by this hook."
    ],
    timeout: [
      type: :pos_integer,
      default: 30_000,
      doc: "Milliseconds before hook is killed."
    ],
    env: [
      type: {:map, :string, :string},
      default: %{},
      doc: "Extra env vars passed to hook process."
    ]
  ]

  @top_schema [
    hooks: [
      type: :keyword_list,
      required: true,
      doc: "Per-stage hook list. Keys must be valid git stages."
    ],
    parallel: [
      type: :boolean,
      default: false,
      doc: "Run hooks within a stage concurrently."
    ],
    fail_fast: [
      type: :boolean,
      default: false,
      doc: "Stop stage on first hook failure."
    ],
    skip_env: [
      type: :string,
      default: "GIT_HOOX",
      doc: "Env var name. Set to `0` to disable all hooks."
    ]
  ]

  @spec top_schema() :: keyword()
  def top_schema, do: @top_schema

  @spec hook_opts_schema() :: keyword()
  def hook_opts_schema, do: @hook_opts_schema

  @spec valid_stages() :: [atom()]
  def valid_stages, do: @stages

  @doc """
  Parse a kebab- or snake-case stage string into its canonical atom.

  Returns `:error` if `stage` does not match any value in `valid_stages/0`.
  Atoms are never created from untrusted input — only known stages are
  returned.
  """
  @spec parse_stage(String.t()) :: {:ok, atom()} | :error
  def parse_stage(stage) when is_binary(stage) do
    normalized = String.replace(stage, "-", "_")

    case Enum.find(@stages, fn s -> Atom.to_string(s) == normalized end) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end
end
