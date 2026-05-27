defmodule GitHoox.Glob do
  @moduledoc """
  Path glob matching used by hook `:files` filters.

  Supported tokens:

    * `**/` — zero or more leading directory segments
    * `**`  — any sequence of characters, including `/`
    * `*`   — any sequence of characters within a single segment
    * `?`   — exactly one non-`/` character

  All other characters are matched literally; regex metacharacters in the
  pattern are escaped before token expansion, so a literal `.` or `+` in the
  pattern matches itself.
  """

  @doc """
  Return true if `file` matches `pattern`.

  Anchored at both ends — partial matches do not count.

  ## Examples

      iex> GitHoox.Glob.match?("lib/foo.ex", "lib/*.ex")
      true

      iex> GitHoox.Glob.match?("lib/nested/bar.ex", "lib/**/*.ex")
      true

      iex> GitHoox.Glob.match?("README.md", "lib/**/*.ex")
      false

  """
  @spec match?(GitHoox.path(), GitHoox.glob()) :: boolean()
  def match?(file, pattern) when is_binary(file) and is_binary(pattern) do
    Regex.match?(compile(pattern), file)
  end

  @doc """
  Compile `pattern` to an anchored `Regex.t()`.

  Call this once per pattern when matching against many files — otherwise
  use `match?/2`, which compiles on every call.
  """
  @spec compile(GitHoox.glob()) :: Regex.t()
  def compile(pattern) when is_binary(pattern) do
    body =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*/", "(?:.*/)?")
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")
      |> String.replace("\\?", "[^/]")

    Regex.compile!("\\A" <> body <> "\\z")
  end
end
