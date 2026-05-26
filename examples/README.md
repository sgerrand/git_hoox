# GitHoox examples

Drop-in custom hooks demonstrating common patterns. Copy a file into your
project (anywhere on the compile path), then register it in `.git_hoox.exs`:

```elixir
%{
  hooks: [
    pre_commit: [
      {MyApp.Hooks.Sobelow, []},
      {MyApp.Hooks.Coverage, threshold: 80}
    ],
    commit_msg: [
      {MyApp.Hooks.JiraTicket, prefix: "PROJ-"}
    ]
  ]
}
```

| File | Stage | What it does |
|------|-------|--------------|
| [`sobelow.ex`](sobelow.ex) | `pre_commit` | Runs `mix sobelow --exit Low` against staged Elixir files. |
| [`coverage.ex`](coverage.ex) | `pre_push` | Runs `mix coveralls` and fails if total coverage drops below `:threshold`. |
| [`jira_ticket.ex`](jira_ticket.ex) | `commit_msg` | Rejects commit messages missing a `PROJ-1234` style ticket prefix. |

These are not packaged with GitHoox — copy what you need and edit freely.
