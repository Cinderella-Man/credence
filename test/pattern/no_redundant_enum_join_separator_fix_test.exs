defmodule Credence.Pattern.NoRedundantEnumJoinSeparatorFixTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Pattern.NoRedundantEnumJoinSeparator.check(ast, [])
  end

  defp fix(code) do
    Credence.Pattern.NoRedundantEnumJoinSeparator.fix(code, [])
  end

  defp assert_fix(input, expected) do
    result = fix(input)
    norm = &(&1 |> Code.string_to_quoted!() |> Macro.to_string())

    assert norm.(result) == norm.(expected),
           "Fix mismatch.\nInput:    #{input}\nExpected: #{expected}\nGot:      #{result}"
  end

  # ── Enum.join ──────────────────────────────────────────────────

  describe "Enum.join" do
    test "direct: Enum.join(list, \"\") → Enum.join(list)" do
      assert_fix(
        "Enum.join(list, \"\")",
        "Enum.join(list)"
      )
    end

    test "single-step pipe collapses: list |> Enum.join(\"\") → Enum.join(list)" do
      assert_fix(
        "list |> Enum.join(\"\")",
        "Enum.join(list)"
      )
    end

    test "multi-step pipe keeps pipe: list |> Enum.reverse() |> Enum.join(\"\") → ... |> Enum.join()" do
      assert_fix(
        "list |> Enum.reverse() |> Enum.join(\"\")",
        "list |> Enum.reverse() |> Enum.join()"
      )
    end
  end

  # ── Enum.map_join ──────────────────────────────────────────────

  describe "Enum.map_join" do
    test "direct: Enum.map_join(list, \"\", mapper) → Enum.map_join(list, mapper)" do
      assert_fix(
        "Enum.map_join(list, \"\", &to_string/1)",
        "Enum.map_join(list, &to_string/1)"
      )
    end

    test "single-step pipe collapses: list |> Enum.map_join(\"\", mapper) → Enum.map_join(list, mapper)" do
      assert_fix(
        "list |> Enum.map_join(\"\", &to_string/1)",
        "Enum.map_join(list, &to_string/1)"
      )
    end

    test "multi-step pipe keeps pipe" do
      assert_fix(
        "list |> Enum.reverse() |> Enum.map_join(\"\", &to_string/1)",
        "list |> Enum.reverse() |> Enum.map_join(&to_string/1)"
      )
    end

    test "inline fn mapper" do
      result = fix("Enum.map_join(list, \"\", fn x -> String.upcase(x) end)")
      norm = &(&1 |> Code.string_to_quoted!() |> Macro.to_string())
      assert norm.(result) == norm.("Enum.map_join(list, fn x -> String.upcase(x) end)")
    end
  end

  # ── all four patterns ──────────────────────────────────────────

  describe "all four patterns together" do
    test "fixes all in one module" do
      result =
        fix("""
        defmodule M do
          def f(a, b) do
            x = Enum.join(a, "")
            y = b |> Enum.join("")
            z = Enum.map_join(a, "", &to_string/1)
            w = b |> Enum.map_join("", &to_string/1)
            {x, y, z, w}
          end
        end
        """)

      assert result =~ "Enum.join(a)"
      assert result =~ "Enum.join(b)"
      assert result =~ "Enum.map_join(a, &to_string/1)"
      assert result =~ "Enum.map_join(b, &to_string/1)"
      refute result =~ "Enum.join(a, \"\")"
      refute result =~ "Enum.join(\"\")"
      refute result =~ "Enum.map_join(a, \"\", &to_string/1)"
      refute result =~ "Enum.map_join(\"\", &to_string/1)"
      refute result =~ "|>"
    end
  end

  # ── no-ops ─────────────────────────────────────────────────────

  describe "no-ops" do
    test "preserves non-empty separator" do
      assert_fix(
        "Enum.join(list, \", \")",
        "Enum.join(list, \", \")"
      )
    end

    test "preserves surrounding code" do
      result =
        fix("""
        defmodule M do
          @moduledoc "Test module"
          def process(list), do: Enum.join(list, "")
          def other(x), do: x + 1
        end
        """)

      assert result =~ "@moduledoc"
      assert result =~ "def other(x)"
      assert result =~ "Enum.join(list)"
      refute result =~ "Enum.join(list, \"\")"
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

      first = fix(input)
      assert fix(first) == first
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

      result = fix(input)

      refute result =~ ~s|Enum.join(list, "")|
      assert result =~ "Enum.join(list)"
      assert result =~ ~s|@doc \"""|
      refute result =~ ~s|@doc "Joins|
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

      result = fix(input)

      assert result =~ "Enum.join(list)"
      refute result =~ "|>"
      assert result =~ ~s|@moduledoc \"""|
      refute result =~ ~s|@moduledoc "This|
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

      assert check(fix(code)) == []
    end

    test "fixed code is valid Elixir" do
      code = """
      defmodule Example do
        def a(l), do: Enum.join(l, "")
        def b(l), do: l |> Enum.map_join("", &to_string/1)
      end
      """

      assert {:ok, _} = Code.string_to_quoted(fix(code))
    end
  end
end
