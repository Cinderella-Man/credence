defmodule Credence.Pattern.NoRecursiveCaseWithoutEmptyListClauseFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoRecursiveCaseWithoutEmptyListClause

  # ═══════════════════════════════════════════════════════════════════
  # FIXABLE — case on a list with [head | tail] but no [] clause
  # ═══════════════════════════════════════════════════════════════════

  test "rewrites the anti-pattern from the spec example" do
    input = """
    defmodule Solution do
      def pop_larger_chars_helper(stack, seen, char, counts) do
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
      end
    end
    """

    expected = """
    defmodule Solution do
      def pop_larger_chars_helper(stack, seen, char, counts) do
        case stack do
          [] ->
            {[], MapSet.new()}

          [top | rest] ->
            remaining = Map.get(counts, top, 0)

            if top > char and remaining > 0 do
              new_seen = MapSet.delete(seen, top)
              pop_larger_chars_helper(rest, new_seen, char, counts)
            else
              {stack, seen}
            end
        end
      end
    end
    """

    assert fix(NoRecursiveCaseWithoutEmptyListClause, input) == expected
  end

  test "rewrites simple case with cons pattern only" do
    input = """
    case stack do
      [top | rest] ->
        process(top, rest)
    end
    """

    expected = """
    case stack do
      [] ->
        {[], MapSet.new()}

      [top | rest] ->
        process(top, rest)
    end
    """

    assert fix(NoRecursiveCaseWithoutEmptyListClause, input) == expected
  end

  # ═══════════════════════════════════════════════════════════════════
  # NOT FIXABLE — left exactly as-is
  # ═══════════════════════════════════════════════════════════════════

  test "leaves code alone when [] clause is already present" do
    code = """
    case stack do
      [] ->
        :ok
      [top | rest] ->
        process(top, rest)
    end
    """

    assert fix(NoRecursiveCaseWithoutEmptyListClause, code) == code
  end

  test "leaves code alone when case has no cons pattern" do
    code = """
    case value do
      :ok -> :success
      :error -> :failure
    end
    """

    assert fix(NoRecursiveCaseWithoutEmptyListClause, code) == code
  end
end
