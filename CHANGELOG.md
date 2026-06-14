# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.0](https://github.com/sgerrand/git_hoox/compare/v0.4.2...v0.5.0) (2026-06-14)


### Features

* **hooks:** add Mix hook for arbitrary mix tasks ([d8954be](https://github.com/sgerrand/git_hoox/commit/d8954be7babce77a4166566aae977fcab222bb24))
* **hooks:** forward :args to mix in Test/Format/Credo/Dialyzer ([74efdcc](https://github.com/sgerrand/git_hoox/commit/74efdcc480c730c1829948d341dc4e47353ce250))
* **installer:** add auto_deps_get to self-heal stale dep locks ([cd1884a](https://github.com/sgerrand/git_hoox/commit/cd1884af31ed6caca823eee6994927fbad1753fb))
* **telemetry:** split :hook :skip into its own event ([e134bad](https://github.com/sgerrand/git_hoox/commit/e134bad216da8d084f1a01cbdcb8e4fd0bf813fd))


### Bug Fixes

* **ci:** key dialyzer PLT cache on resolved OTP/Elixir versions ([5358432](https://github.com/sgerrand/git_hoox/commit/5358432a487be34e3233e183d4950246e8d0a1fd))
* **config:** handle malformed config errors ([6403ff1](https://github.com/sgerrand/git_hoox/commit/6403ff1b65829fd13bf28b2f943a9baa53a6d764))
* **hooks:** default Hooks.Mix :files so Runner can dispatch ([197a3e6](https://github.com/sgerrand/git_hoox/commit/197a3e6e6b7410661937eb24714aac4c4252e5a5))
* **installer:** propagate Git.toplevel error from scaffold ([ac2599c](https://github.com/sgerrand/git_hoox/commit/ac2599c490002f52ddac1e3b35dc42c3ade73853))
* **installer:** restrict backup restore to ISO8601-suffixed siblings ([ff1bc94](https://github.com/sgerrand/git_hoox/commit/ff1bc946b714f7652157cdd12d571720bc5500ce))
* **runner:** return missing_args error instead of crashing ([b17a813](https://github.com/sgerrand/git_hoox/commit/b17a813e245c34a4119f2dc31c530925d90463c8))


### Refactor

* **config:** normalize hook options at load time ([01341a8](https://github.com/sgerrand/git_hoox/commit/01341a8f026996a432c91317ccbccac37dc1e89d))
* **config:** use implicit try in eval_config ([36ad1f1](https://github.com/sgerrand/git_hoox/commit/36ad1f12cb9aa5f3d0aa9fbf53c89e4f8a08611f))
* **hook:** tighten run/2 return contract ([44dafca](https://github.com/sgerrand/git_hoox/commit/44dafca1957662449fc6e9b1dd0695e22d282216))


### Documentation

* document :args opt and Hooks.Mix module ([a88196e](https://github.com/sgerrand/git_hoox/commit/a88196e1dae4a96da490608b3fa114f0d902f50d))

## [0.4.2](https://github.com/sgerrand/git_hoox/compare/v0.4.1...v0.4.2) (2026-05-27)


### Bug Fixes

* **cmd:** redirect child stdin to /dev/null ([74d663c](https://github.com/sgerrand/git_hoox/commit/74d663cd1da3b8c03cb02fd83d639cc2ee8166a7))


### Documentation

* **ex_doc:** use README as package docs landing page ([1e7d086](https://github.com/sgerrand/git_hoox/commit/1e7d0864ff51ca8f51bef91e93e4f1eae5a82c81))

## [0.4.1](https://github.com/sgerrand/git_hoox/compare/v0.4.0...v0.4.1) (2026-05-27)


### Refactor

* **bench:** collapse telemetry handlers via record/3 ([a39cc29](https://github.com/sgerrand/git_hoox/commit/a39cc29f67045ba9796edd19c6cfec329d7b52b0))
* **cmd:** expose decode_message/6 to cover the :DOWN branch ([337410c](https://github.com/sgerrand/git_hoox/commit/337410cdb22e6f6b1dc5dc6d031edd75eb921724))
* **config:** extract validate_with/4 and memoize global keys ([20d5ae0](https://github.com/sgerrand/git_hoox/commit/20d5ae05e49a9fc057d80769559eff61ab655469))
* **doctor:** fold shim existence and mode into one File.stat ([18e7374](https://github.com/sgerrand/git_hoox/commit/18e7374d07e9a08c6adfad1c2a4d75765b4276fb))
* **doctor:** reuse Installer.managed?/1 and hook_names/0 ([dfa93e9](https://github.com/sgerrand/git_hoox/commit/dfa93e98827aaf41f5b01cbc798d3c76e4c127dc))
* **hooks/shell:** drive expand/2 from a token table ([102dbda](https://github.com/sgerrand/git_hoox/commit/102dbdaa36dd8197ba26a1af3ff4525163705bf7))
* **mix/bench:** route stage through Schema; derive table from [@cols](https://github.com/cols) ([302f620](https://github.com/sgerrand/git_hoox/commit/302f6206193e7b4c20cab85c9fda7c69b7b39321))
* **mix/run:** drop unreachable print_failure catch-all ([379d571](https://github.com/sgerrand/git_hoox/commit/379d57176db0cf83294705b25d030cae40ab0681))
* **schema:** add parse_stage/1 for kebab-or-snake input ([be8bdd0](https://github.com/sgerrand/git_hoox/commit/be8bdd0f92c56c1a142be4b268a8d2c0a350d587))

## [0.4.0](https://github.com/sgerrand/git_hoox/compare/v0.3.0...v0.4.0) (2026-05-27)


### Features

* **doctor:** flag managed shims missing the executable bit ([958d800](https://github.com/sgerrand/git_hoox/commit/958d800be204b504a77c4950cac373286021e4ba))


### Bug Fixes

* **cmd:** return {msg, 127} for missing executables ([61a6690](https://github.com/sgerrand/git_hoox/commit/61a6690f26a7364d59f4e109886978112ea13897))
* **hooks/test:** scope :related with no matches no longer runs full suite ([091b4b7](https://github.com/sgerrand/git_hoox/commit/091b4b75494b0a112f77d529fd53544bb4601967))
* **mix/run:** validate stage against Schema before atom conversion ([8e4e7d0](https://github.com/sgerrand/git_hoox/commit/8e4e7d06667d63648666aa754fac17477f1661f7))
* **runner:** honor fail_fast on parallel stage runs ([831c6a2](https://github.com/sgerrand/git_hoox/commit/831c6a2d3b213de637b3686bed87a83e3cd71fbc))


### Performance

* **runner:** precompile glob patterns once per hook ([0fba30c](https://github.com/sgerrand/git_hoox/commit/0fba30c33208609b7f967007ec9bd6fa689a9045))


### Refactor

* **cmd:** monitor the port to avoid wedging on detached stdio ([5cd5f0c](https://github.com/sgerrand/git_hoox/commit/5cd5f0cee4921b12413b1cfb43700ae77755810d))
* **git:** handle pre-push delete refs explicitly ([f8b4b54](https://github.com/sgerrand/git_hoox/commit/f8b4b5426c6fd61cb519cad4f15ba41b5e26c37b))
* **hook:** centralize merge_defaults helper ([7b07fd8](https://github.com/sgerrand/git_hoox/commit/7b07fd8954e33dc1b6c44c8b72831f81fefe77b5))
* **hooks/test:** hoist map_to_test regexes to module attrs ([5aeed59](https://github.com/sgerrand/git_hoox/commit/5aeed5986e02a8bb22d91b535677f878f6982244))
* **hooks:** extract Helpers.to_result/1 for Cmd.run results ([cebef86](https://github.com/sgerrand/git_hoox/commit/cebef866e96d3de7673188d44f68317760997a5c))
* **installer:** truncate backup timestamp via DateTime.truncate ([fd4c2ab](https://github.com/sgerrand/git_hoox/commit/fd4c2abd2032cbb058dba9fdce72d4968210c671))
* **runner:** collapse serial result-ordering to single reverse ([172530a](https://github.com/sgerrand/git_hoox/commit/172530ae6f141a6f3ab276d9223413ffe750d2ce))
* **runner:** move config-error rendering to the mix task ([ff40ace](https://github.com/sgerrand/git_hoox/commit/ff40aceb880a8ddb1ad7a4eb8c8fdb0bcdcf904d))

## [0.3.0](https://github.com/sgerrand/git_hoox/compare/v0.2.0...v0.3.0) (2026-05-26)


### Features

* add mix git_hoox.bench for per-hook timing percentiles ([3b4e7db](https://github.com/sgerrand/git_hoox/commit/3b4e7dbcf50100f9ec0373946911f09c3b8f3871))
* emit telemetry around stages and hooks ([578d69d](https://github.com/sgerrand/git_hoox/commit/578d69dd298eef6ea33e31e2f7e80e21cdfc95d2))
* **shell:** support {push_files} template token ([1bc2add](https://github.com/sgerrand/git_hoox/commit/1bc2add6c398d9bd475a87f8fc23a69741d4d4d6))
* stream hook stdout live via GitHoox.Cmd ([1438fcb](https://github.com/sgerrand/git_hoox/commit/1438fcb726586a90d1803bfcaa8322fab6912da7))
* **telemetry:** fire :hook :exception on timeout and crash ([e51f2e2](https://github.com/sgerrand/git_hoox/commit/e51f2e25540c3ac6bc192a46facaf1e2f471b51a))


### Bug Fixes

* stop parallel hooks interleaving each other's stdout ([8613f5c](https://github.com/sgerrand/git_hoox/commit/8613f5c1980a1f6a34a59ad29756937f42adf9ef))
* stop Shell hook running with empty token substitution ([b82328f](https://github.com/sgerrand/git_hoox/commit/b82328fbe94a74341ee574055396fcdd4cd76331))


### Refactor

* drop unreachable error clauses in install + run tasks ([c222e4f](https://github.com/sgerrand/git_hoox/commit/c222e4f98feba21049d36676f6d166b115ffde01))


### Documentation

* **shell:** drop ex_doc reference to private invoke fn ([f17f03c](https://github.com/sgerrand/git_hoox/commit/f17f03c7795b427f725c6d1c59dfbab968582159))

## [0.2.0](https://github.com/sgerrand/git_hoox/compare/v0.1.0...v0.2.0) (2026-05-26)


### Features

* add mix git_hoox.doctor for setup diagnostics ([5969d70](https://github.com/sgerrand/git_hoox/commit/5969d705b6203e1fa56c9df4b1ceeaf634d14248))
* add mix git_hoox.list to print resolved hook config ([20ecd8a](https://github.com/sgerrand/git_hoox/commit/20ecd8adca4735e6c22f94201a856c3233a58d62))
* add workflow_dispatch pre-release workflow ([fed34f8](https://github.com/sgerrand/git_hoox/commit/fed34f8afbf46ed595ff852ff9bdea8c90d4c74f))
* **ci:** support next-version prerelease channel ([edd0ce1](https://github.com/sgerrand/git_hoox/commit/edd0ce1d6e674a8a0366aaa81bdc99a70c6002f4))
* extract Glob module with StreamData property tests ([c901d82](https://github.com/sgerrand/git_hoox/commit/c901d827b07a9c7bcfe785683bf5f0e665f501b3))
* validate hook-specific opts via opts_schema/0 callback ([e33aa39](https://github.com/sgerrand/git_hoox/commit/e33aa39b60c1040b522eb594b819cbc15586b83a))


### Bug Fixes

* **ci:** make prerelease atomic and trigger publish workflow ([23bb0c9](https://github.com/sgerrand/git_hoox/commit/23bb0c9db77a4468722426efd1c999caa4f32b4c))
* default Format glob to match nested files ([d7334c3](https://github.com/sgerrand/git_hoox/commit/d7334c3b280e98cfd4cbdfcb0915ad3d79791743))


### Documentation

* add examples/ directory with sample custom hooks ([e85b662](https://github.com/sgerrand/git_hoox/commit/e85b662597486b7338eb4119700907399e958933))
* link examples/ to GitHub to fix mix docs warning ([8ccb436](https://github.com/sgerrand/git_hoox/commit/8ccb436fe16f2357b8fa3c78c444b6b8806a0e39))

## [0.1.0](https://github.com/sgerrand/git_hoox/compare/22c259bd...v0.1.0) (2026-05-21)


### Features

* dispatch files per stage and enforce hook timeouts ([d646a03](https://github.com/sgerrand/git_hoox/commit/d646a03dd8d67aa557eba36ab8fe531b9df3daa8))
* forward :env opt to hook subprocesses ([3c5b442](https://github.com/sgerrand/git_hoox/commit/3c5b4424401621884146e68d4c1ccb4dafd8e7f4))
* initial version with hooks, runner, installer, and CI ([22c259b](https://github.com/sgerrand/git_hoox/commit/22c259bd129dedf0fa57cf5f52d0d62ef2eadd4e))
* scaffold a starter .git_hoox.exs via install --scaffold ([d64f8b7](https://github.com/sgerrand/git_hoox/commit/d64f8b79c3a0b8c2aeb5f149ad81883ad95cc941))


### Bug Fixes

* **ci:** read version from mix.exs without booting mix ([02428fb](https://github.com/sgerrand/git_hoox/commit/02428fb639f64eead86472bc2f42c8c3d5686d43))
* clear dialyzer warnings on uninstall path ([30ee293](https://github.com/sgerrand/git_hoox/commit/30ee293a751fc759c39965f3df25dd219c4e6cc5))


### Refactor

* address credo --strict findings ([b0e381e](https://github.com/sgerrand/git_hoox/commit/b0e381e1655f924ddea5e5125b25b373ac20c1f3))


### Documentation

* add CLAUDE.md with commands and architecture overview ([faa3157](https://github.com/sgerrand/git_hoox/commit/faa31576a3d32e4cb64bf2827ac063343f71a0cc))
* add GitHub funding metadata ([971bcb5](https://github.com/sgerrand/git_hoox/commit/971bcb51f631e71a7f8fc19148cc9b8a6382a750))
* fix mix docs --warnings-as-errors ([406ee8e](https://github.com/sgerrand/git_hoox/commit/406ee8e5e17210fbb3ac1adb3d0de49a249f0169))
