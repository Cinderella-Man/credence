defmodule Credence.Syntax.FixMisplacedWhenGuardAnalyzeTest do
  use ExUnit.Case, async: true

  alias Credence.Issue
  alias Credence.Syntax.FixMisplacedWhenGuard

  defp analyze(code), do: FixMisplacedWhenGuard.analyze(code)

  describe "flags the clause-head shape" do
    test "the field sample" do
      assert [%Issue{rule: :fix_misplaced_when_guard}] =
               analyze("def positive?(x), when x > 0, do: true")
    end

    test "defp" do
      assert analyze("defp ok?(x), when is_atom(x), do: true") != []
    end

    # The comma sits on the PREVIOUS line here, which is why the locator works on
    # absolute offsets rather than searching within the error's own line.
    test "split across lines, comma on the line above" do
      assert analyze("""
             def f(x),
               when x > 0,
               do: x
             """) != []
    end

    test "a case clause" do
      assert analyze("""
             case x do
               y, when y > 0 -> y
             end
             """) != []
    end

    test "an anonymous function clause" do
      assert analyze("fn y, when y > 0 -> y end") != []
    end
  end

  describe "flags the for-filter shape" do
    test "the field sample" do
      assert [%Issue{rule: :fix_misplaced_when_guard}] =
               analyze("""
               for {name, price} <- items, when price > 100 do
                 name
               end
               """)
    end

    # A `)` immediately before the comma does NOT mean this is a clause head — the
    # locator tracks bracket depth, so the balanced `f()` is skipped and `for` is
    # still the enclosing keyword.
    test "when the generator ends in a call" do
      assert analyze("""
             for a <- f(), when a > 1 do
               a
             end
             """) != []
    end

    test "a for nested inside a def body resolves to the for" do
      assert analyze("""
             def g(l) do
               for a <- l, when a > 1 do
                 a
               end
             end
             """) != []
    end
  end

  describe "reports one issue per repair" do
    test "two clause heads" do
      assert length(
               analyze("""
               defmodule B do
                 def a(x), when x > 0, do: 1
                 def b(y), when y > 0, do: 2
               end
               """)
             ) == 2
    end

    test "two filters in one comprehension" do
      assert length(
               analyze("""
               for x <- l, when x > 1, when x < 9 do
                 x
               end
               """)
             ) == 2
    end

    test "both shapes in one file" do
      assert length(
               analyze("""
               defmodule C do
                 def g(l) do
                   for a <- l, when a > 1, do: a
                 end

                 def h(x), when x > 0, do: x
               end
               """)
             ) == 2
    end
  end

  describe "declines" do
    test "source that parses" do
      assert analyze("def f(x) when x > 0, do: x") == []
    end

    # `when` in a generator PATTERN is valid Elixir and must not be touched. This is
    # the form the defect is often confused with.
    test "a valid when in a generator pattern" do
      assert analyze("for {a, b} when b > 1 <- list, do: a") == []
    end

    # Neither repair is correct for `with`: deleting the comma does not compile, and
    # deleting the `when` compiles while silently dropping the guard, because a bare
    # `with` clause's value is discarded. Executed in WhenGuardPosition's moduledoc.
    test "a with clause, where neither repair preserves intent" do
      assert analyze("""
             with {:ok, x} <- f(), when x > 0 do
               x
             end
             """) == []
    end

    test "a when inside a string, with an unrelated parse error elsewhere" do
      assert analyze("""
             x = \"a when b\"
             y = (
             """) == []
    end

    test "a when inside a comment, with an unrelated parse error elsewhere" do
      assert analyze("""
             # guard with when here
             y = (
             """) == []
    end

    test "an unrelated syntax error" do
      assert analyze("x = foo((1") == []
    end
  end
end
