# GitHoox

[![Build Status](https://github.com/sgerrand/git_hoox/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/sgerrand/git_hoox/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/sgerrand/git_hoox/badge.svg?branch=main)](https://coveralls.io/github/sgerrand/git_hoox?branch=main)
[![Hex Version](https://img.shields.io/hexpm/v/git_hoox.svg)](https://hex.pm/packages/git_hoox)
[![Hex Docs](https://img.shields.io/badge/docs-hexpm-blue.svg)](https://hexdocs.pm/git_hoox/)

Git hooks in pure Elixir. Configurable file globs, per-hook options, built-in
support for `mix format`, Credo, ExUnit, and Dialyzer, plus a generic
`mix <task>` hook for everything else.

GitHoox aims for parity with [lefthook](https://github.com/evilmartians/lefthook)'s
mental model — no implicit stashing, opt-in re-staging of fixed files — while
keeping the entire toolchain in Elixir so projects do not need a Node or Python
runtime to run hooks.

## Installation

Add `git_hoox` to your dev dependencies in `mix.exs`:

<!-- x-release-please-start-version -->
```elixir
def deps do
  [
    {:git_hoox, "~> 0.5.0", only: [:dev], runtime: false}
  ]
end
```
<!-- x-release-please-end -->


Fetch and install the git hook shims:

```sh
mix deps.get
mix git_hoox.install
```

The installer writes shims into `.git/hooks/` and refuses to overwrite any
existing user-authored hook. Pass `--force` to back up the existing hook
(saved as `<hook>.backup.<utc-timestamp>`) and replace it.

```sh
mix git_hoox.install --force
mix git_hoox.install --dry-run    # show the install plan, write nothing
mix git_hoox.install --scaffold   # also write a starter .git_hoox.exs
```

Pass `--scaffold` (or `-s`) on first install to drop a starter
`.git_hoox.exs` at the repo root. The scaffolder refuses to overwrite an
existing config unless `--force` is set.

## Configuration

GitHoox reads `.git_hoox.exs` at the repo root. The file is a single map.

```elixir
# .git_hoox.exs
%{
  hooks: [
    pre_commit: [
      {GitHoox.Hooks.Format, []},
      {GitHoox.Hooks.Credo, []}
    ],
    pre_push: [
      {GitHoox.Hooks.Test, scope: :stale},
      {GitHoox.Hooks.Dialyzer, []}
    ]
  ],
  parallel: false,
  fail_fast: false
}
```

Top-level options:

| Key         | Type    | Default | Description                                     |
|-------------|---------|---------|-------------------------------------------------|
| `hooks`     | keyword | —       | Per-stage list of `{Module, opts}` entries.     |
| `parallel`  | boolean | `false` | Run hooks within a stage concurrently.          |
| `fail_fast` | boolean | `false` | Stop on first failure within a stage.           |
| `skip_env`  | string  | `"GIT_HOOX"` | Env var consulted for skip/exclude flags.  |
| `auto_deps_get` | boolean | `false` | Fetch locked deps before each hook runs.    |

Supported stages: `pre_commit`, `prepare_commit_msg`, `commit_msg`,
`post_commit`, `pre_rebase`, `post_checkout`, `post_merge`, `pre_push`.

### Keeping deps in sync

When `mix.lock` changes (after a pull or branch switch), the next hook can
fail before it even starts:

```
** (Mix) Can't continue due to errors on dependencies
* ex_doc (Hex package)
  lock mismatch: the dependency is out of date. To fetch locked version run "mix deps.get"
```

The shim runs `mix git_hoox.run`, and Mix refuses that task while deps are
out of date — so no hook can fix it from inside the config.

Set `auto_deps_get: true` to have each shim run `mix deps.get` first, but
only when the lock is out of date (it checks with `--check-locked`, which is
a no-op when the lock already matches). Re-run `mix git_hoox.install` after
changing the flag to regenerate the shims.

This adds one quick Mix call per hook run. Leave it off if you keep deps in
sync by hand.

## Built-in Hooks

### `GitHoox.Hooks.Format`

Runs `mix format` against staged Elixir files and re-stages the result.

```elixir
{GitHoox.Hooks.Format, []}
{GitHoox.Hooks.Format, check_only: true}     # fail instead of mutating
{GitHoox.Hooks.Format, files: ~w(lib/**/*.ex)}
{GitHoox.Hooks.Format, args: ["--dot-formatter", "custom.exs"]}
```

Defaults: `stage_fixed: true`, `files: ~w(**/*.ex **/*.exs **/*.heex)`.

`:args` are inserted between any built-in flag (`--check-formatted`) and
the trailing file list — final shape:
`mix format [--check-formatted] <args...> <files...>`.

### `GitHoox.Hooks.Credo`

Runs `mix credo` against staged Elixir files.

```elixir
{GitHoox.Hooks.Credo, []}
{GitHoox.Hooks.Credo, strict: true}
{GitHoox.Hooks.Credo, strict: true, args: ["--format", "json"]}
```

Defaults: `stage_fixed: false`, `files: ~w(lib/**/*.ex test/**/*.exs)`.

`:args` are inserted before `--files-included` — final shape:
`mix credo [--strict] <args...> --files-included <files...>`.

### `GitHoox.Hooks.Test`

Runs `mix test`. Three selection strategies:

```elixir
{GitHoox.Hooks.Test, scope: :all}        # full suite
{GitHoox.Hooks.Test, scope: :stale}      # mix test --stale (fastest)
{GitHoox.Hooks.Test, scope: :related}    # map staged lib/*.ex to test/*_test.exs
{GitHoox.Hooks.Test, scope: :stale, args: ["--warnings-as-errors"]}
```

Defaults: `stage_fixed: false`, `scope: :all`.

`:args` are spliced after the scope flag and before any related-test
paths — final shape:
`mix test [--stale] <args...> [<related_test_files>]`.

### `GitHoox.Hooks.Dialyzer`

Runs `mix dialyzer --quiet`. **Slow** — PLT builds and whole-project analysis
make this unsuitable for `pre_commit`. Configure on `pre_push`.

```elixir
pre_push: [
  {GitHoox.Hooks.Dialyzer, []},
  {GitHoox.Hooks.Dialyzer, args: ["--halt-exit-status"]}
]
```

`:args` are appended after `--quiet` — final shape:
`mix dialyzer --quiet <args...>`.

### `GitHoox.Hooks.Mix`

Generic escape hatch for `mix` tasks that don't have a dedicated hook
module (`mix docs`, `mix compile --warnings-as-errors`, `mix hex.outdated`,
`mix deps.audit`, …):

```elixir
{GitHoox.Hooks.Mix, task: "compile", args: ["--warnings-as-errors"]}
{GitHoox.Hooks.Mix, task: "docs"}
{GitHoox.Hooks.Mix, task: "hex.outdated"}

# Task accepts paths — opt into file forwarding.
{GitHoox.Hooks.Mix, task: "lint", append_files: true,
                    files: ~w(lib/**/*.ex)}
```

Options:

| Option           | Type    | Default | Description                                              |
|------------------|---------|---------|----------------------------------------------------------|
| `:task`          | string  | —       | Required. Mix task name.                                  |
| `:args`          | list    | `[]`    | Extra CLI args appended after the task name.              |
| `:append_files`  | boolean | `false` | Append the matched file list as trailing arguments.       |

Defaults: `stage_fixed: false`.

When `append_files: true` and the runner passes an empty file list, the
hook returns `:ok` without running mix. This avoids the trailing-space
"scan whole project" trap. `append_files: false` runs the task regardless
of file list.

Prefer the dedicated hooks (`Format`, `Credo`, `Test`, `Dialyzer`) when
they cover the task — they ship sensible defaults and first-class
options. `Hooks.Mix` is the right call when no dedicated module exists
or when you want a one-line shim for a custom task.

### `GitHoox.Hooks.Shell`

Escape hatch for anything not covered by a built-in:

```elixir
{GitHoox.Hooks.Shell,
  run: "mix sobelow --exit",
  files: ~w(lib/**/*.ex)}

{GitHoox.Hooks.Shell,
  run: "mix format {staged_files}",
  files: ~w(*.ex *.exs),
  stage_fixed: true}
```

Template variables expanded in `:run`:

| Variable          | Source                                            |
|-------------------|---------------------------------------------------|
| `{files}`         | paths passed to the hook (stage-specific)         |
| `{staged_files}`  | `git diff --cached --name-only --diff-filter=ACMR` |
| `{all_files}`     | `git ls-files`                                    |
| `{push_files}`    | paths parsed from `pre_push` stdin (pre_push only) |

`{files}` and `{staged_files}` are distinct. `{files}` is whatever the
stage hands the hook (staged paths for `pre_commit`, the commit message
file for `commit_msg`, etc.), while `{staged_files}` always re-runs
`git diff --cached` regardless of stage. If a template references
`{files}` or `{push_files}` and the hook is invoked with no files — or
references `{staged_files}` and `git diff --cached` returns nothing —
the hook returns `:ok` without invoking the shell so commands like
`mix sobelow {files}` cannot silently scan the entire project when the
substitution would have collapsed to an empty argument.

`{push_files}` only makes sense in the `pre_push` stage. Using it on any
other stage causes the hook to return an error so misconfigurations
surface immediately at first dispatch rather than silently expanding to
an empty string.

## Custom Hooks

Implement the `GitHoox.Hook` behaviour:

```elixir
defmodule MyApp.Hooks.Sobelow do
  @behaviour GitHoox.Hook

  @opts_schema [
    confidence: [type: :string, default: "Low",
                 doc: "Minimum severity that fails the build."]
  ]

  @impl true
  def default_opts, do: [files: ~w(lib/**/*.ex), stage_fixed: false]

  @impl true
  def opts_schema, do: @opts_schema

  @impl true
  def run([], _opts), do: :ok
  def run(files, opts) do
    args = ["sobelow", "--exit", Keyword.fetch!(opts, :confidence) | files]

    case System.cmd("mix", args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, code} -> {:error, {code, out}}
    end
  end
end
```

The optional `opts_schema/0` callback declares a
[NimbleOptions](https://hexdocs.pm/nimble_options) schema for any keys
not part of the global hook schema (`:files`, `:stage_fixed`, `:timeout`,
`:env`). Unknown keys, missing required keys, and wrong types surface at
`mix git_hoox.doctor` and `mix git_hoox.run` config-load time. Hooks
that do not implement the callback continue to accept arbitrary extras
without validation.

Register in `.git_hoox.exs`:

```elixir
pre_commit: [
  {MyApp.Hooks.Sobelow, []}
]
```

The [`examples/`](https://github.com/sgerrand/git_hoox/tree/main/examples) directory ships ready-to-copy custom hooks
(Sobelow, ExCoveralls coverage threshold, JIRA ticket enforcement).

Return values:

| Return                  | Meaning                                                  |
|-------------------------|----------------------------------------------------------|
| `:ok`                   | Hook passed, no files modified.                          |
| `{:ok, modified_paths}` | Hook passed; runner re-stages paths if `stage_fixed: true`. |
| `:skip`                 | Hook deliberately did nothing.                           |
| `{:error, reason}`      | Hook failed. Commit aborts unless `fail_fast: false` and other hooks need to run. |

## Partial Stage and `stage_fixed`

GitHoox does **not** stash unstaged changes before running hooks. Hooks see the
working tree as-is. This matches lefthook's default behavior and avoids the
crash and conflict risks of automatic `git stash`/`git stash pop` wrappers.

When a formatter or autofixer mutates a file, set `stage_fixed: true` on that
hook entry to re-`git add` the modified files automatically. Built-in formatter
hooks set this default; opt out per-entry if undesired.

## Skipping Hooks

Set the configured `skip_env` (default `GIT_HOOX`) at commit time:

```sh
GIT_HOOX=0 git commit                       # disable all hooks
GIT_HOOX_EXCLUDE=credo,format git commit    # skip specific hook modules
GIT_HOOX_ONLY=test git push                 # run only one
```

Module names match the suffix after `GitHoox.Hooks.` (lowercased).

## Hook Output

Hooks stream their combined stdout/stderr to the terminal as it arrives,
so a long-running `mix dialyzer` or `mix test` shows progress instead of
fifteen seconds of silence followed by a single error blob.

Streaming is on by default. To suppress it (for example in scripted
contexts where you want only the runner's exit code), set the
application env in your `config/config.exs`:

```elixir
config :git_hoox, stream_output: false
```

`parallel: true` mode buffers each hook's output and flushes it as a
single block once the hook finishes, in completion order. Output stays
readable — no chunk-level interleaving — but you pay for it in latency:
nothing appears on the terminal until the fastest hook completes. If
live progress matters more than tidy output, stay on serial dispatch.

## Observability

GitHoox emits `:telemetry` events around every stage and every hook, with no
default handler attached. Attach the reference `Logger`-backed handler with
`GitHoox.Logger.attach/0`, or roll your own — the event shape is documented
on `GitHoox.Telemetry`.

```elixir
# Reference Logger output.
GitHoox.Logger.attach()

# Or a custom one, e.g. for shipping timings to a metrics backend.
:telemetry.attach(
  "git-hoox-timings",
  [:git_hoox, :hook, :stop],
  fn _ev, %{duration: d}, %{module: mod, result: r}, _ ->
    ms = System.convert_time_unit(d, :native, :millisecond)
    :ok = MyMetrics.observe("git_hoox.hook", ms, mod: mod, result: r)
  end,
  nil
)
```

## Diagnose Setup Issues

```sh
mix git_hoox.doctor
```

Reports the state of the git repo, hooks directory, installed shims,
config file, and config validity. Exits non-zero only on hard errors
(e.g. malformed `.git_hoox.exs`); missing shims or missing config surface
as `[warn]` lines so the task is safe to run from CI as a sanity check.

## Inspect Resolved Config

```sh
mix git_hoox.list
```

Loads `.git_hoox.exs`, merges each hook's `default_opts/0` with your
overrides, and prints the result grouped by stage. Useful for confirming
that an opt you set is actually being passed to the hook.

## Benchmark Hooks

```sh
mix git_hoox.bench                      # pre_commit, 5 runs
mix git_hoox.bench --stage pre_push     # different stage
mix git_hoox.bench --runs 20            # more samples
mix git_hoox.bench -s commit-msg -n 3
```

Attaches a `:telemetry` handler, dispatches `mix git_hoox.run <stage>`
the requested number of times, and prints per-hook timing statistics
(`runs`, `errors`, `p50`, `p95`, `max`, `mean`, `total`) sorted by total
time. Use it when deciding whether a hook is cheap enough to keep on
`pre_commit` or should move to `pre_push`.

## Uninstall

```sh
mix git_hoox.uninstall
```

Removes only the shims GitHoox installed (identified by a marker comment).
Foreign hooks are left untouched. If a `.backup.*` file exists alongside a
removed shim, the most recent backup is restored.

## Status

GitHoox is pre-1.0. The public API surface (`GitHoox`, `GitHoox.Hook`,
`GitHoox.Config`, `GitHoox.Git`, `GitHoox.Installer`, the built-in hook modules,
and the `mix git_hoox.*` tasks) follows semver from 0.1.0 onward, but internals
under modules marked `@moduledoc false` (e.g. config schema) may change without notice.

Pre-releases are cut on demand via the Pre-release GitHub Action
(`workflow_dispatch`) and published to Hex with the standard
`-rc.N`/`-beta.N`/`-alpha.N` semver suffix, so you can pin a release
candidate with `{:git_hoox, "0.2.0-rc.1"}` before the stable cut. A
rolling `-next.N` channel is also supported — dispatching the workflow
with version `0.3.0-next` auto-increments the trailing counter from the
existing tags on origin.

Documentation is published to [HexDocs](https://hexdocs.pm/git_hoox).

## Changelog

Released versions are recorded in [CHANGELOG.md](CHANGELOG.md), generated by
[release-please](https://github.com/googleapis/release-please).

Unreleased changes accumulate in the open
[Release PR](https://github.com/sgerrand/git_hoox/pulls?q=is%3Apr+is%3Aopen+label%3A%22autorelease%3A+pending%22),
which release-please refreshes on every push to `main` and rewrites the
upcoming version and CHANGELOG entries into.

## License

BSD 2-Clause. See [LICENSE](LICENSE).
