# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

GitHoox is a pure-Elixir git hooks runner. It writes shell shims into
`.git/hooks/*` that exec back into `mix git_hoox.run <stage>`, which loads
`.git_hoox.exs`, resolves the file set for that stage, and dispatches each
configured hook. Design goal: lefthook parity (no implicit stashing, opt-in
re-staging) without requiring a Node or Python runtime.

Elixir `~> 1.17` (CI tests 1.17, 1.18, 1.19 on OTP 26/27).

## Commands

```sh
mix deps.get
mix compile --warnings-as-errors
mix test                              # full suite, excludes :slow/:network
mix test --include slow               # include slow-tagged tests (Dialyzer hook, big fixtures)
mix test test/git_hoox/runner_test.exs           # single file
mix test test/git_hoox/runner_test.exs:42        # single test by line
mix format --check-formatted
mix credo --strict
mix dialyzer                          # first run builds PLT (~20s); cached after
mix docs                              # ex_doc HTML output to doc/
```

All four quality gates (`format --check-formatted`, `credo --strict`,
`dialyzer`, `test`) must pass before committing. CI enforces them.

## Architecture

The runtime path on a real commit:

1. Git invokes `.git/hooks/pre-commit` (shim written by `Installer`, identified
   by the `# git_hoox managed` marker).
2. Shim execs `mix git_hoox.run pre-commit "$@"` — positional args are kept;
   for `pre-push`, stdin is inherited and read by the mix task.
3. `Mix.Tasks.GitHoox.Run` parses the stage atom, captures args, reads stdin
   when relevant, and calls `GitHoox.Runner.run/3`.
4. `Runner` loads `.git_hoox.exs` via `GitHoox.Config`, resolves the file set
   via `Runner.files_for_stage/3` (per-stage dispatch — `pre_commit` uses
   staged files, `commit_msg` uses the message path from `args[0]`, `pre_push`
   parses stdin, etc.), filters hooks via skip env vars (`GIT_HOOX`,
   `GIT_HOOX_EXCLUDE`, `GIT_HOOX_ONLY`), and dispatches.
5. Each hook is invoked inside `Task.async`/`Task.yield` with the per-hook
   `:timeout` (default 30s); timeouts surface as `{:error, {:timeout, ms}}`.
   Hooks returning `{:ok, modified}` get their files re-staged via
   `Git.restage/1` when `stage_fixed: true`.

Key modules:

- `GitHoox.Hook` — `@callback run(files, opts)` + optional `default_opts/0`.
  Built-in hooks (`GitHoox.Hooks.{Format,Credo,Test,Dialyzer,Shell}`) all
  implement this and share `GitHoox.Hooks.Helpers.env_opt/1` for forwarding
  the per-hook `:env` map to `System.cmd`.
- `GitHoox.Config` — loads `.git_hoox.exs` via `Code.eval_file/1`. Validates
  the top-level shape and the global hook opts (`files`/`stage_fixed`/
  `timeout`/`env`) against `GitHoox.Config.Schema`. Hook-specific opts (the
  rest) are validated against the hook's optional `opts_schema/0` callback
  if present — hooks that omit the callback accept arbitrary extras without
  validation. All built-in hooks declare a schema; the in-test fixtures
  (`Pass`, `Fail`, `Slow`, etc.) intentionally do not, which keeps them
  permissive enough to accept ad-hoc `:reason`/`:sleep_ms` opts.
- `GitHoox.Git` — thin wrapper around `git` via `System.cmd`. All file
  listings use `-z` + null-split to handle filenames with spaces.
- `GitHoox.Installer` — writes shims for all 8 stages; refuses to overwrite
  foreign hooks unless `:force`, in which case it backs up to
  `<hook>.backup.<utc-iso8601>`. `scaffold/1` writes a starter `.git_hoox.exs`.
- `GitHoox.Glob` — hand-rolled `match?/2` for hook `:files` filters. Supports
  `**/`, `**`, `*`, `?`. Covered by `test/git_hoox/glob_test.exs` with
  concrete cases, doctests, and StreamData properties (the "match? never
  raises on arbitrary printable inputs" property is the main fuzz harness).

`examples/` holds copy-paste custom hooks (Sobelow, coverage, JIRA ticket).
They are not packaged with the library — `package.files` in `mix.exs` does
not list `examples/` — so referenced modules use the `MyApp.Hooks.*`
namespace as a convention for users adopting them.

`GitHoox.Doctor` and `mix git_hoox.doctor` provide a one-shot health check:
git repo presence, hooks directory state, shim ownership (managed vs.
foreign), config presence, config validity. The mix task exits 1 only on
`:error` severity; `:warn` (missing shims or config) is non-fatal, so the
task is safe to call from CI.

`mix git_hoox.list` is the debug companion to `doctor`: it loads the
config, merges each hook's defaults with user opts, and prints the result
grouped by stage. Use it when an opt seems ignored or when verifying that
a glob covers the files you expect.

`GitHoox.Runner.run_one/3` merges a synthetic `:__stage__` key into the
opts keyword before calling each hook, so hooks that need stage context
(currently only `GitHoox.Hooks.Shell` for its `{push_files}` validation)
can read it. The key is implementation detail — custom hooks are free to
ignore it, but it is reserved.

`GitHoox.Telemetry` emits `[:git_hoox, :stage, :start | :stop | :exception]`
and `[:git_hoox, :hook, :start | :stop | :exception]` events via
`:telemetry.span/3`. No handler is attached by default; `GitHoox.Logger`
is the reference handler (`GitHoox.Logger.attach/0`). Stage events log at
`:info`/`:warning`; hook events log at `:debug`/`:warning`. The
`Runner.run_one/3` flow always goes through `Telemetry.hook_span/4`, so a
hook with no matched files still emits a `:skip` stop event — useful for
verifying that a glob filtered out everything.

## Tests

`GitHoox.Case` (`test/support/case.ex`) sets up a real temporary git repo per
test via `GitHoox.GitFixture`. Tests that mutate the process cwd via
`File.cd!/2` must be `async: false`. The fixture sets a hermetic env
(`GIT_CONFIG_GLOBAL=/dev/null`, fixed author/committer dates) so behavior is
deterministic across machines. `GitFixture.set_config/3` and
`worktree_add/3` exist for tests that exercise `core.hooksPath` or linked
worktree paths. Note that git shares `.git/hooks` across all worktrees by
default; per-worktree isolation requires setting `core.hooksPath` on the
worktree explicitly.

Test-only hook modules live in `test/support/hooks.ex`: `Pass`, `Fail`,
`MutateAndReport`, `Counter`, `RecordFiles`, `Slow`. They are loaded via
`elixirc_paths(:test)` and are not packaged.

## Commits

Conventional Commits format, enforced by `committed` (`committed.toml`):
- `style = "conventional"`, subject ≤72, lines ≤72
- Allowed types: `feat`, `fix`, `perf`, `deps`, `refactor`, `docs`, `chore`,
  `test`, `ci`, `build`, `revert`
- `subject_capitalized = false`, `imperative_subject = true`

Do not include a `Co-Authored-By:` trailer on commits.

## Releases

Driven by `release-baton` (GitHub App) wrapping `release-please`. Pushes to
`main` open a Release PR with version bump + CHANGELOG. Merging cuts a tag,
which triggers `.github/workflows/publish.yml` (gated by the `hex`
environment) to run `mix hex.publish`. The publish job verifies the tag
matches `mix.exs @version` before uploading.

Pre-1.0 semver via release-please: `fix:` → patch, `feat:` → minor,
`feat!:`/`BREAKING CHANGE:` → minor (not major).

### Cutting a pre-release

`.github/workflows/prerelease.yml` is a `workflow_dispatch` job that accepts
an `X.Y.Z-(rc|beta|alpha).N` version input, bumps `@version` in `mix.exs`,
creates the branch `prerelease/vX.Y.Z-rc.N`, pushes it, then calls
`gh release create --target <branch>` so the tag and pre-release land
together. This ordering matters: pushing the tag separately and then
calling `gh release create` leaves an orphan tag if the release step
fails. Two further nuances:

- The workflow mints a release-baton GitHub App token via
  `actions/create-github-app-token` and uses it for both `git push` and
  `gh release create`. Default `GITHUB_TOKEN` actions in a workflow
  cannot trigger downstream workflows, so a release created with the
  default token would not fire `release: published` and `publish.yml`
  would silently never run. The app token bypasses that restriction.
- The existing `publish.yml` fires on `release: published` for both
  stable and pre-release types and pushes the package to Hex. Stable
  release flow via `release-please` is unaffected — release-please only
  operates on `main`, so the prerelease branch coexists.

Trigger via `gh workflow run prerelease.yml -f version=0.2.0-rc.1` or via
the Actions tab. The workflow refuses if the tag already exists or if the
version does not match the expected shape.

Accepted version shapes:

- Explicit: `X.Y.Z-(rc|beta|alpha|next|pre|dev).N` (e.g. `0.2.0-rc.1`,
  `0.3.0-beta.3`, `0.3.0-next.7`).
- Next-channel shorthand: `X.Y.Z-next` (no trailing `.N`). The workflow
  scans existing `vX.Y.Z-next.M` tags on origin and bumps `M` by one, so
  successive dispatches of `0.3.0-next` cut `0.3.0-next.1`, `.2`, `.3`,
  ... without the caller tracking the counter.

The next-channel pattern gives you a rolling "what's on `main` right
now" prerelease stream. Stable releases via release-please are still
the source of truth on `main`; `next` tags live on per-cut prerelease
branches and are not merged back.

## GitHub Actions

All workflow `uses:` references are pinned to commit SHAs with a `# vX.Y.Z`
comment for human readers and Dependabot. Dependabot is configured for both
`github-actions` and `mix` ecosystems with a 7-day cooldown and grouped
version/security updates.
