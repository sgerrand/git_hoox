# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
