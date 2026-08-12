# Git exports GIT_DIR, GIT_INDEX_FILE, GIT_PREFIX and friends into every
# hook it runs, so `mix test` invoked from a git hook inherits them. Any
# `git` call the suite makes — GitFixture, GitHoox.Git.restage/1, a hook
# shelling out — would then target the real repository instead of the
# temp repo it was given, writing test fixtures into the real index.
# Clear the whole namespace before ExUnit starts; keep our own GIT_HOOX
# skip vars, which tests set and read deliberately.
System.get_env()
|> Map.keys()
|> Enum.filter(&String.starts_with?(&1, "GIT_"))
|> Enum.reject(&String.starts_with?(&1, "GIT_HOOX"))
|> Enum.each(&System.delete_env/1)

Application.put_env(:git_hoox, :stream_output, false)
Application.put_env(:git_hoox, :reporter, false)
ExUnit.start(exclude: [:slow, :network])
