defmodule GitHoox.GlobTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias GitHoox.Glob

  doctest GitHoox.Glob

  describe "concrete cases" do
    test "exact literal match" do
      assert Glob.match?("README.md", "README.md")
      refute Glob.match?("README.md", "readme.md")
    end

    test "* matches within one segment" do
      assert Glob.match?("foo.ex", "*.ex")
      refute Glob.match?("lib/foo.ex", "*.ex")
    end

    test "** matches across segments" do
      assert Glob.match?("lib/foo.ex", "lib/**")
      assert Glob.match?("lib/nested/deep/foo.ex", "lib/**")
    end

    test "**/ matches zero or more leading segments" do
      assert Glob.match?("foo.ex", "**/*.ex")
      assert Glob.match?("lib/foo.ex", "**/*.ex")
      assert Glob.match?("lib/a/b/foo.ex", "**/*.ex")
    end

    test "lib/**/*.ex matches lib and nested .ex" do
      assert Glob.match?("lib/foo.ex", "lib/**/*.ex")
      assert Glob.match?("lib/nested/foo.ex", "lib/**/*.ex")
      refute Glob.match?("test/foo.ex", "lib/**/*.ex")
      refute Glob.match?("lib/foo.exs", "lib/**/*.ex")
    end

    test "? matches exactly one non-slash char" do
      assert Glob.match?("a.ex", "?.ex")
      refute Glob.match?(".ex", "?.ex")
      refute Glob.match?("ab.ex", "?.ex")
      refute Glob.match?("a/.ex", "?.ex")
    end

    test "regex metacharacters in pattern are literal" do
      assert Glob.match?("a.b.c", "a.b.c")
      refute Glob.match?("axb.c", "a.b.c")
      assert Glob.match?("a+b", "a+b")
      assert Glob.match?("foo(x)", "foo(x)")
    end

    test "anchored at both ends" do
      refute Glob.match?("lib/foo.ex", "foo.ex")
      refute Glob.match?("foo.ex.bak", "*.ex")
    end

    test "** alone matches anything (including empty)" do
      assert Glob.match?("", "**")
      assert Glob.match?("foo", "**")
      assert Glob.match?("lib/a/b", "**")
    end

    test "empty pattern only matches empty string" do
      assert Glob.match?("", "")
      refute Glob.match?("a", "")
    end
  end

  describe "properties" do
    property "literal pattern matches itself" do
      check all(path <- safe_path()) do
        assert Glob.match?(path, path)
      end
    end

    property "** matches every safe path" do
      check all(path <- safe_path()) do
        assert Glob.match?(path, "**")
      end
    end

    property "*.ex matches single-segment .ex files but not nested" do
      check all(stem <- safe_segment()) do
        path = stem <> ".ex"
        assert Glob.match?(path, "*.ex")
        nested = "dir/" <> path
        refute Glob.match?(nested, "*.ex")
      end
    end

    property "**/*.ex matches any-depth .ex files" do
      check all(
              segs <- list_of(safe_segment(), min_length: 1, max_length: 5),
              stem <- safe_segment()
            ) do
        path = Enum.join(segs ++ [stem <> ".ex"], "/")
        assert Glob.match?(path, "**/*.ex")
      end
    end

    property "match? never raises on arbitrary printable inputs" do
      check all(
              path <- string(:printable, max_length: 64),
              pattern <- string(:printable, max_length: 32)
            ) do
        assert is_boolean(Glob.match?(path, pattern))
      end
    end
  end

  defp safe_segment do
    string(:alphanumeric, min_length: 1, max_length: 12)
  end

  defp safe_path do
    list_of(safe_segment(), min_length: 1, max_length: 5)
    |> map(&Enum.join(&1, "/"))
  end
end
