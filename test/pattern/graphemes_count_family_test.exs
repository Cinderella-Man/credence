defmodule Credence.Pattern.GraphemesCountFamilyTest do
  @moduledoc """
  Three rules can claim "count the characters in a string", and docs/12's C11
  listed them as a duplicate cluster to be folded. Running them says otherwise:
  they converge. This file pins the convergence, because nothing did, and
  because the property is what makes the "duplicate" reading wrong.

    * `AvoidGraphemesEnumCount` — `Enum.count(String.graphemes(s))`
    * `AvoidGraphemesLength`    — `length(String.graphemes(s))`
    * `NoEnumCountForLength`    — `Enum.count(any provably-list)`, which the
      grapheme call also satisfies

  The overlap is real and only the third rule's answer is weaker: it rewrites
  to `length(String.graphemes(s))`, keeping the list allocation the other two
  remove. What makes that harmless is the Pattern round being a **cascade** —
  the weaker output is itself a `length(String.graphemes(…))`, which
  `AvoidGraphemesLength` then finishes. So the family reaches `String.length/1`
  from any starting point and in any order.

  That distinction matters for a rename. Today `AvoidGraphemes*` also happens to
  sort ahead of `NoEnumCountForLength`, so the strong rule usually wins outright
  — the same accidental-alphabetical ordering T1.2 found across the Semantic
  round. Here it is not load-bearing, and the last test is what proves it:
  starting *from* the weaker rewrite still lands on `String.length/1`.
  """
  use Credence.RuleCase, async: true

  alias Credence.Pattern.AvoidGraphemesEnumCount
  alias Credence.Pattern.AvoidGraphemesLength
  alias Credence.Pattern.NoEnumCountForLength

  describe "every entry point converges on String.length/1" do
    test "Enum.count(String.graphemes(s))" do
      code = """
      defmodule GraphemesEnumCountEntry do
        def f(s), do: Enum.count(String.graphemes(s))
      end
      """

      assert Credence.fix(code).code =~ "String.length(s)"
    end

    test "length(String.graphemes(s))" do
      code = """
      defmodule GraphemesLengthEntry do
        def f(s), do: length(String.graphemes(s))
      end
      """

      assert Credence.fix(code).code =~ "String.length(s)"
    end

    test "the pipeline spelling" do
      code = """
      defmodule GraphemesPipelineEntry do
        def f(s), do: s |> String.graphemes() |> Enum.count()
      end
      """

      assert Credence.fix(code).code =~ "String.length(s)"
    end
  end

  describe "the overlap is real, and the weaker answer is not the shipped one" do
    test "all three rules claim the piped Enum.count form" do
      code = """
      defmodule GraphemesOverlapClaims do
        def f(text), do: String.graphemes(text) |> Enum.count()
      end
      """

      assert flagged?(AvoidGraphemesEnumCount, code)
      assert flagged?(NoEnumCountForLength, code)
    end

    test "NoEnumCountForLength alone keeps the allocation the others remove" do
      code = """
      defmodule GraphemesWeakerAnswer do
        def f(text), do: String.graphemes(text) |> Enum.count()
      end
      """

      weaker = fix(NoEnumCountForLength, code)

      # It swaps the counter and keeps the pipe, so the grapheme list is still
      # built — `String.length/1` never materialises one.
      assert weaker =~ "String.graphemes(text) |> length()"
      refute weaker =~ "String.length(text)"
    end

    test "and the cascade finishes it anyway — this is what survives a rename" do
      # Deliberately starting from the weaker rewrite rather than the original,
      # i.e. the world where NoEnumCountForLength had sorted first.
      weaker = """
      defmodule GraphemesCascadeFinish do
        def f(text), do: String.graphemes(text) |> length()
      end
      """

      fixed = Credence.fix(weaker)

      assert fixed.code =~ "String.length(text)"
      assert {AvoidGraphemesLength, 1} in fixed.applied_rules
    end
  end
end
