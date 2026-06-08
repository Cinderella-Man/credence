defmodule Credence.Pattern.NoRedundantEnumJoinSeparatorFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRedundantEnumJoinSeparator

  # ── Enum.join ──────────────────────────────────────────────────

  describe "Enum.join" do
    test "direct: Enum.join(list, \"\") → Enum.join(list)" do
      assert fix(NoRedundantEnumJoinSeparator, """
             Enum.join(list, "")
             """) == """
             Enum.join(list)
             """
    end

    test "single-step pipe collapses: list |> Enum.join(\"\") → Enum.join(list)" do
      assert fix(NoRedundantEnumJoinSeparator, """
             list |> Enum.join("")
             """) == """
             Enum.join(list)
             """
    end

    test "multi-step pipe keeps pipe: list |> Enum.reverse() |> Enum.join(\"\") → ... |> Enum.join()" do
      assert fix(NoRedundantEnumJoinSeparator, """
             list |> Enum.reverse() |> Enum.join("")
             """) ==
               """
               list |> Enum.reverse() |> Enum.join()
               """
    end
  end

  # ── Enum.map_join ──────────────────────────────────────────────

  describe "Enum.map_join" do
    test "direct: Enum.map_join(list, \"\", mapper) → Enum.map_join(list, mapper)" do
      assert fix(NoRedundantEnumJoinSeparator, """
             Enum.map_join(list, "", &to_string/1)
             """) ==
               """
               Enum.map_join(list, &to_string/1)
               """
    end

    test "single-step pipe collapses: list |> Enum.map_join(\"\", mapper) → Enum.map_join(list, mapper)" do
      assert fix(NoRedundantEnumJoinSeparator, """
             list |> Enum.map_join("", &to_string/1)
             """) ==
               """
               Enum.map_join(list, &to_string/1)
               """
    end

    test "multi-step pipe keeps pipe" do
      assert fix(
               NoRedundantEnumJoinSeparator,
               """
               list |> Enum.reverse() |> Enum.map_join("", &to_string/1)
               """
             ) == """
             list |> Enum.reverse() |> Enum.map_join(&to_string/1)
             """
    end

    test "inline fn mapper" do
      assert fix(
               NoRedundantEnumJoinSeparator,
               """
               Enum.map_join(list, "", fn x -> String.upcase(x) end)
               """
             ) == """
             Enum.map_join(list, fn x -> String.upcase(x) end)
             """
    end
  end

  # ── all four patterns ──────────────────────────────────────────

  describe "all four patterns together" do
    test "fixes all in one module" do
      input = """
      defmodule M do
        def f(a, b) do
          x = Enum.join(a, "")
          y = b |> Enum.join("")
          z = Enum.map_join(a, "", &to_string/1)
          w = b |> Enum.map_join("", &to_string/1)
          {x, y, z, w}
        end
      end
      """

      expected = """
      defmodule M do
        def f(a, b) do
          x = Enum.join(a)
          y = Enum.join(b)
          z = Enum.map_join(a, &to_string/1)
          w = Enum.map_join(b, &to_string/1)
          {x, y, z, w}
        end
      end
      """

      assert fix(NoRedundantEnumJoinSeparator, input) == expected
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "preserves non-empty separator" do
      assert fix(NoRedundantEnumJoinSeparator, """
             Enum.join(list, ", ")
             """) ==
               """
               Enum.join(list, ", ")
               """
    end

    test "preserves surrounding code" do
      input = """
      defmodule M do
        @moduledoc "Test module"
        def process(list), do: Enum.join(list, "")
        def other(x), do: x + 1
      end
      """

      expected = """
      defmodule M do
        @moduledoc "Test module"
        def process(list), do: Enum.join(list)
        def other(x), do: x + 1
      end
      """

      assert fix(NoRedundantEnumJoinSeparator, input) == expected
    end
  end

  # ── idempotent ─────────────────────────────────────────────────

  describe "idempotent" do
    test "second pass produces same result" do
      input = """
      defmodule M do
        def f(a, b) do
          x = Enum.join(a, "")
          y = b |> Enum.join("")
          z = Enum.map_join(a, "", &to_string/1)
          w = b |> Enum.map_join("", &to_string/1)
          {x, y, z, w}
        end
      end
      """

      first = fix(NoRedundantEnumJoinSeparator, input)
      assert fix(NoRedundantEnumJoinSeparator, first) == first
    end
  end

  # ── heredoc preservation (regression) ──────────────────────────

  describe "heredoc preservation (regression)" do
    test "fix does not collapse @doc heredoc" do
      input = """
      defmodule Example do
        @doc \"""
        Joins a list of strings into a single string.

        Returns a binary.
        \"""
        def run(list) do
          Enum.join(list, "")
        end
      end
      """

      expected = """
      defmodule Example do
        @doc \"""
        Joins a list of strings into a single string.

        Returns a binary.
        \"""
        def run(list) do
          Enum.join(list)
        end
      end
      """

      # Exact compare proves the @doc heredoc is preserved (not collapsed to a string).
      assert fix(NoRedundantEnumJoinSeparator, input) == expected
    end

    test "fix does not collapse @moduledoc heredoc" do
      input = """
      defmodule Example do
        @moduledoc \"""
        This module does things.

        It does them well.
        \"""

        def run(list), do: list |> Enum.join("")
      end
      """

      expected = """
      defmodule Example do
        @moduledoc \"""
        This module does things.

        It does them well.
        \"""

        def run(list), do: Enum.join(list)
      end
      """

      # Exact compare proves the @moduledoc heredoc is preserved.
      assert fix(NoRedundantEnumJoinSeparator, input) == expected
    end
  end

  # ── round-trip ─────────────────────────────────────────────────

  describe "round-trip" do
    test "fixed code produces zero issues" do
      code = """
      defmodule Example do
        def a(l), do: Enum.join(l, "")
        def b(l), do: l |> Enum.join("")
        def c(l), do: Enum.map_join(l, "", &to_string/1)
        def d(l), do: l |> Enum.map_join("", &to_string/1)
      end
      """

      assert check(NoRedundantEnumJoinSeparator, fix(NoRedundantEnumJoinSeparator, code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(l), do: Enum.join(l, "")
        def b(l), do: l |> Enum.map_join("", &to_string/1)
      end
      """

      assert valid_syntax?(fix(NoRedundantEnumJoinSeparator, code))
    end
  end
end
