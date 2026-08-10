%{
  hooks: [
    pre_commit: [
      {GitHoox.Hooks.Format, []},
      {GitHoox.Hooks.Credo, strict: true},
      {GitHoox.Hooks.Mix, task: "compile", args: ["--warnings-as-errors"]},
      {GitHoox.Hooks.Mix, task: "deps.unlock", args: ["--check-unused"]}
    ],
    pre_push: [
      # The suite spins up real temp git repos and takes well over the
      # 30s default on a cold build.
      {GitHoox.Hooks.Test, scope: :stale, timeout: 300_000}
    ]
  ]
}
