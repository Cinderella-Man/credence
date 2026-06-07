defmodule Credence.Pattern.NoListDuplicateFlattenCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Issue
  alias Credence.Pattern.NoListDuplicateFlatten

  # ═══════════════════════════════════════════════════════════════════
  # POSITIVE — should flag: Enum.concat(List.duplicate(var, <pos int>))
  # ═══════════════════════════════════════════════════════════════════

  describe "flags Enum.concat of List.duplicate with a literal count" do
    test "piped form with integer literal" do
      assert flagged?(NoListDuplicateFlatten, """
             def tile(list) do
               list
               |> List.duplicate(3)
               |> Enum.concat()
             end
             """)
    end

    test "nested form with integer literal" do
      assert flagged?(NoListDuplicateFlatten, """
             def tile(list) do
               Enum.concat(List.duplicate(list, 3))
             end
             """)
    end

    test "issue carries the rule name" do
      assert [%Issue{rule: :no_list_duplicate_flatten}] =
               check(NoListDuplicateFlatten, """
               Enum.concat(List.duplicate(list, 2))
               """)
    end
  end

  # ═══════════════════════════════════════════════════════════════════
  # NEGATIVE — must NOT flag (no safe, same-answer fix exists)
  # ═══════════════════════════════════════════════════════════════════

  describe "does not flag List.flatten variants (deep flatten != flat_map)" do
    # List.flatten recurses; Enum.flat_map merges one level only, so they
    # disagree the moment the list holds nested lists. Never rewritten.
    test "piped List.duplicate |> List.flatten" do
      assert clean?(NoListDuplicateFlatten, """
             def tile(list) do
               list
               |> List.duplicate(3)
               |> List.flatten()
             end
             """)
    end

    test "nested List.flatten(List.duplicate(...))" do
      assert clean?(NoListDuplicateFlatten, """
             def tile(list) do
               List.flatten(List.duplicate(list, 3))
             end
             """)
    end
  end

  describe "does not flag a non-literal repetition count" do
    # `1..n` is wrong for n == 0 (descending range) and for negative n
    # (List.duplicate raises, the range does not), so a runtime variable
    # count has no provably-safe rewrite.
    test "piped form with variable count" do
      assert clean?(NoListDuplicateFlatten, """
             def repeat(chars, times) do
               chars
               |> List.duplicate(times)
               |> Enum.concat()
             end
             """)
    end

    test "nested form with variable count" do
      assert clean?(NoListDuplicateFlatten, """
             def tile(list, n) do
               Enum.concat(List.duplicate(list, n))
             end
             """)
    end

    test "zero literal count" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.concat(List.duplicate(list, 0))
             """)
    end

    test "negative literal count" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.concat(List.duplicate(list, -1))
             """)
    end
  end

  describe "does not flag when the duplicated value is not a bare variable" do
    # The closure re-evaluates the value n times; only a side-effect-free
    # variable reference is safe to move into it.
    test "duplicated value is a function call" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.concat(List.duplicate(build_list(), 3))
             """)
    end

    test "duplicated value is a list literal" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.concat(List.duplicate([1, 2, 3], 3))
             """)
    end

    test "longer pipeline before List.duplicate" do
      assert clean?(NoListDuplicateFlatten, """
             def build(list) do
               list
               |> Enum.map(&to_string/1)
               |> List.duplicate(3)
               |> Enum.concat()
             end
             """)
    end
  end

  describe "does not flag unrelated shapes" do
    test "standalone List.duplicate" do
      assert clean?(NoListDuplicateFlatten, """
             List.duplicate(list, 3)
             """)
    end

    test "standalone Enum.concat" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.concat(lists)
             """)
    end

    test "Enum.concat of two lists" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.concat(a, b)
             """)
    end

    test "List.duplicate piped to something else" do
      assert clean?(NoListDuplicateFlatten, """
             def dup(list) do
               list
               |> List.duplicate(3)
               |> List.last()
             end
             """)
    end

    test "already idiomatic Enum.flat_map" do
      assert clean?(NoListDuplicateFlatten, """
             Enum.flat_map(1..3, fn _ -> list end)
             """)
    end
  end
end
