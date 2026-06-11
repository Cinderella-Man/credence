defmodule Credence.Pattern.NoRecursiveCaseWithoutEmptyListClauseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRecursiveCaseWithoutEmptyListClause

  # ═══════════════════════════════════════════════════════════════════
  # FLAGGED — case on a list with [head | tail] but no [] clause
  # ═══════════════════════════════════════════════════════════════════

  test "flags case with cons pattern but missing empty list clause" do
    assert flagged?(NoRecursiveCaseWithoutEmptyListClause, """
    case stack do
      [top | rest] ->
        process(top, rest)
    end
    """)
  end

  test "flags the anti-pattern in the spec example" do
    assert flagged?(NoRecursiveCaseWithoutEmptyListClause, """
    case stack do
      [top | rest] ->
        remaining = Map.get(counts, top, 0)

        if top > char and remaining > 0 do
          new_seen = MapSet.delete(seen, top)
          pop_larger_chars_helper(rest, new_seen, char, counts)
        else
          {stack, seen}
        end
    end
    """)
  end

  # ═══════════════════════════════════════════════════════════════════
  # CLEAN — case already has [] clause or doesn't use cons pattern
  # ═══════════════════════════════════════════════════════════════════

  test "leaves code alone when [] clause is present" do
    assert clean?(NoRecursiveCaseWithoutEmptyListClause, """
    case stack do
      [] ->
        :ok
      [top | rest] ->
        process(top, rest)
    end
    """)
  end

  test "leaves code alone when case has no cons pattern" do
    assert clean?(NoRecursiveCaseWithoutEmptyListClause, """
    case value do
      :ok -> :success
      :error -> :failure
    end
    """)
  end

  test "leaves code alone when case matches on non-list" do
    assert clean?(NoRecursiveCaseWithoutEmptyListClause, """
    case result do
      {:ok, val} -> val
      {:error, reason} -> reason
    end
    """)
  end
end
