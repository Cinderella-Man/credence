defmodule Credence.EquivalenceRegressionTest do
  @moduledoc """
  Proof that our safety checks can actually catch a bad rewrite.

  Every rule has a test under `test/pattern/*_equivalence_test.exs` that passes,
  showing the rule's rewrite is safe. But all of those passing only proves the
  *good* rewrites get accepted — it does not prove the checks would *reject* a bad
  one. A check that never says "no" is worthless.

  This file proves they say "no". We take rules that were tried and **rejected**
  because their rewrite changed what the code does (listed in
  `maintainer_tools/unfixable_confirmed.md`; the rules and their tests still live
  in the sister project `../credence_evolution`). For each, we rebuild the
  rejected rewrite as a `before`/`broken` pair of code snippets and show that
  running the two on one carefully chosen input gives **different results**. That
  difference is exactly what would have failed the rule's safety check.

  We do not run the rule itself — most of these rules only flagged the problem and
  never wrote an automatic fix, and some were deleted. We just run the two
  snippets and compare. `eval_outcome/1` (from the checker module) turns each run
  into a comparable result: `{:ok, value}` if it returned, `{:raise, Error}` if it
  crashed.

  A passing test here means "the two versions really do give different results" —
  i.e. our checks would have caught this rewrite. See
  `docs/07-behaviour-equivalence-harness.md` §Verification → "Historical
  regression check".
  """

  use ExUnit.Case, async: true

  import Credence.BehaviourEquivalence, only: [eval_outcome: 1]

  # Run `expr` (a snippet with one variable named `var`) on `input` and return the
  # result: `{:ok, value}` if it returned, `{:raise, Error}` if it crashed.
  defp outcome(expr, var, input) do
    eval_outcome(fn -> compile(expr, var).(input) end)
  end

  # Turn the snippet string into a callable function `fn <var> -> <expr> end`.
  # Some `broken` snippets ignore the variable (e.g. the plain `true`), which would
  # print an "unused variable" warning — `capture_io(:stderr, ...)` hides that.
  defp compile(expr, var) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      {fun, _binding} = Code.eval_string("fn #{var} -> (#{expr}) end")
      send(self(), {:compiled, fun})
    end)

    receive do
      {:compiled, fun} -> fun
    end
  end

  # Check that the original (`before`) and the rejected rewrite (`broken`) give
  # different results on `input`. Returns both results so each test can also pin
  # the exact values. If they happen to match, the rewrite was actually safe on
  # this input — that is worth knowing, so don't invent a fake input to force a
  # difference.
  defp assert_diverges(before, broken, var, input) do
    o = outcome(before, var, input)
    n = outcome(broken, var, input)

    refute o === n,
           """
           Expected the original and the rejected rewrite to give different
           results, but they matched on #{inspect(input)}:
             before (#{before}) => #{inspect(o)}
             broken (#{broken}) => #{inspect(n)}
           If the rewrite really doesn't differ on any real input, that is a
           finding worth recording — don't invent a fake input to force it.
           """

    {o, n}
  end

  describe "avoid_charlist_for_iteration — gives numbers instead of letters" do
    # The rejected rewrite swapped `String.to_charlist` for `String.graphemes`.
    # `to_charlist` turns "abc" into the character codes [97, 98, 99]; `graphemes`
    # turns it into the letters ["a", "b", "c"]. Different results, even for plain
    # ASCII. (Reason in unfixable_confirmed.md: "value-type change ... on every
    # input incl. ASCII; no safe subset.")
    test "input \"abc\": numbers [97, 98, 99] vs letters [\"a\", \"b\", \"c\"]" do
      before = "s |> String.to_charlist()"
      broken = "s |> String.graphemes()"

      {o, n} = assert_diverges(before, broken, :s, "abc")

      # Pin the exact results so the kind of difference is documented, not just detected.
      assert o === {:ok, [97, 98, 99]}
      assert n === {:ok, ["a", "b", "c"]}
    end
  end

  describe "no_reverse_uniq_reverse — keeps a different copy when there are duplicates" do
    # The rejected rewrite replaced `reverse |> uniq |> reverse` (removes duplicates,
    # keeping the LAST copy of each) with plain `uniq` (keeps the FIRST). On
    # [1, 2, 1, 3] that changes the order of the result.
    test "input [1, 2, 1, 3]: [2, 1, 3] (keeps last) vs [1, 2, 3] (keeps first)" do
      before = "list |> Enum.reverse() |> Enum.uniq() |> Enum.reverse()"
      broken = "Enum.uniq(list)"

      {o, n} = assert_diverges(before, broken, :list, [1, 2, 1, 3])

      assert o === {:ok, [2, 1, 3]}
      assert n === {:ok, [1, 2, 3]}
    end
  end

  describe "no_group_by_identity — returns counts instead of grouped lists" do
    # The rejected rewrite replaced `Enum.group_by(list, & &1)` with
    # `Enum.frequencies(list)`. group_by returns "value => list of copies";
    # frequencies returns "value => count". Different shapes for any non-empty list.
    test "input [1, 1]: %{1 => [1, 1]} vs %{1 => 2}" do
      before = "Enum.group_by(list, & &1)"
      broken = "Enum.frequencies(list)"

      {o, n} = assert_diverges(before, broken, :list, [1, 1])

      assert o === {:ok, %{1 => [1, 1]}}
      assert n === {:ok, %{1 => 2}}
    end
  end

  describe "no_redundant_sort_comparator — crashes instead of sorting" do
    # The rejected rewrite dropped the custom comparison function and used plain
    # `Enum.sort`. The comparison `fn [a, b], [c, d] -> ...` only matches 2-element
    # lists; on [[1], [2]] it crashes, but plain `Enum.sort` happily sorts them.
    # (The reason file also notes a number-ordering difference, but that one varies
    # from run to run, so we pin this reliable crash-vs-sorts case instead.)
    test "input [[1], [2]]: crashes (FunctionClauseError) vs sorts to [[1], [2]]" do
      before = "Enum.sort(list, fn [a, b], [c, d] -> a < c or (a == c and b < d) end)"
      broken = "Enum.sort(list)"

      {o, n} = assert_diverges(before, broken, :list, [[1], [2]])

      assert o === {:raise, FunctionClauseError}
      assert n === {:ok, [[1], [2]]}
    end
  end

  describe "no_starts_with_own_prefix — returns true instead of crashing" do
    # The rule spots `String.starts_with?(x, String.slice(x, 0, n))`, which is
    # always true *when x is a string*. The rejected fix replaced the whole thing
    # with `true`. But x isn't guaranteed to be a string: on a non-string like the
    # atom :abc, the original crashes (String.slice rejects it) while `true` does not.
    test "input :abc (not a string): crashes (FunctionClauseError) vs true" do
      before = "String.starts_with?(x, String.slice(x, 0, 2))"
      broken = "true"

      {o, n} = assert_diverges(before, broken, :x, :abc)

      assert o === {:raise, FunctionClauseError}
      assert n === {:ok, true}
    end
  end

  describe "avoid_graphemes_for_byte_iteration — crashes on multi-byte characters" do
    # The rejected rewrite swapped `String.graphemes` (letters) for
    # `String.to_charlist` (character codes) when the loop pulls a byte out with
    # `<<char>>`. On a multi-byte character like "é", the graphemes version crashes
    # (its byte pattern can't match a 2-byte letter) while to_charlist returns the
    # single code [233]. (Plain ASCII gives the same answer either way, so the input
    # has to be a multi-byte character to show the difference.)
    test "input \"é\" (multi-byte): crashes (FunctionClauseError) vs [233]" do
      before = "s |> String.graphemes() |> Enum.map(fn <<char>> -> char end)"
      broken = "s |> String.to_charlist() |> Enum.map(fn char -> char end)"

      {o, n} = assert_diverges(before, broken, :s, "é")

      assert o === {:raise, FunctionClauseError}
      assert n === {:ok, [233]}
    end
  end

  describe "no_integer_to_string_contains — crashes with a different error" do
    # The rejected rewrite checked "does this number's digits contain 5?" by switching
    # from `String.contains?(Integer.to_string(n), "5")` to digit arithmetic on
    # `Integer.digits(n)`. On something that isn't an integer, both crash — but with
    # *different* errors: the original's `Integer.to_string(:x)` raises ArgumentError,
    # the rewrite's `Integer.digits(:x)` raises FunctionClauseError. This is the one
    # case the other tests don't cover: the checker telling two different crashes apart
    # (it compares only the error type, so these must come out as different).
    test "input :x (not an integer): ArgumentError vs FunctionClauseError" do
      before = ~s|String.contains?(Integer.to_string(n), "5")|
      broken = "Enum.member?(Integer.digits(n), 5)"

      {o, n} = assert_diverges(before, broken, :n, :x)

      assert o === {:raise, ArgumentError}
      assert n === {:raise, FunctionClauseError}
    end
  end

  describe "no_enum_at_in_reduce — returns a value where the rewrite crashes" do
    # This stands in for the biggest family of rejected rules: replacing
    # `Enum.at(list, i)` with `elem(List.to_tuple(list), i)`. `Enum.at` is forgiving —
    # a negative index counts from the end, and an index past the end returns `nil`.
    # `elem` is strict and crashes in both of those cases. So the rewrite turns a
    # quiet answer into a crash.
    test "index -1: last element (3) vs crash; index 9: nil vs crash" do
      before = "Enum.at(list, -1)"
      broken = "elem(List.to_tuple(list), -1)"

      {o, n} = assert_diverges(before, broken, :list, [1, 2, 3])
      assert o === {:ok, 3}
      assert n === {:raise, ArgumentError}

      # Same rewrite, index past the end: Enum.at returns nil, elem crashes.
      {o2, n2} = assert_diverges("Enum.at(list, 9)", "elem(List.to_tuple(list), 9)", :list, [1, 2, 3])
      assert o2 === {:ok, nil}
      assert n2 === {:raise, ArgumentError}
    end
  end
end
