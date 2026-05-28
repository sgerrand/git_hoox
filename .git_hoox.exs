%{
  hooks: [
    pre_commit: [
      {GitHoox.Hooks.Format, []},
      {GitHoox.Hooks.Credo, strict: true},
      {GitHoox.Hooks.Mix, task: "compile", args: ["--warnings-as-errors"]},
      {GitHoox.Hooks.Mix, task: "deps.unlock", args: ["--check-unused"]}
    ],
    pre_push: [
      {GitHoox.Hooks.Test, scope: :stale}
    ]
  ]
}
