%{
  hooks: [
    pre_commit: [
      {GitHoox.Hooks.Format, []},
      {GitHoox.Hooks.Credo, []}
    ],
    pre_push: [
      {GitHoox.Hooks.Test, scope: :stale}
    ]
  ]
}
