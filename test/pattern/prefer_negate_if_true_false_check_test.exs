defmodule Credence.Pattern.PreferNegateIfTrueFalseCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferNegateIfTrueFalse

  test "flags the anti-pattern" do
    assert flagged?(PreferNegateIfTrueFalse, """
           if MapSet.member?(seen, current) do
             false
           else
             MapSet.put(seen, current)
             |> loop(sum_of_squared_digits(current))
           end
           """)
  end

  test "leaves good code alone" do
    assert clean?(PreferNegateIfTrueFalse, """
           if !MapSet.member?(seen, current) do
             MapSet.put(seen, current)
             |> loop(sum_of_squared_digits(current))
           end
           """)
  end

  test "flags the anti-pattern with a binary condition" do
    assert flagged?(PreferNegateIfTrueFalse, """
           if len_a != len_b do
             false
           else
             do_work(a, b)
           end
           """)
  end

  test "does not fire when else branch is missing" do
    assert clean?(PreferNegateIfTrueFalse, """
           if cond do
             false
           end
           """)
  end

  # De-dup with no_if_true_false: when the condition is provably boolean AND the
  # else body is a boolean literal/expression, no_if_true_false collapses the
  # whole `if` to a bare boolean. We stay out so the two rules never both patch
  # the same node.
  test "does not fire when no_if_true_false handles it (boolean cond, else true)" do
    assert clean?(PreferNegateIfTrueFalse, """
           if a == b do
             false
           else
             true
           end
           """)
  end

  test "does not fire when no_if_true_false handles it (boolean cond, boolean-expr else)" do
    assert clean?(PreferNegateIfTrueFalse, """
           if a > b do
             false
           else
             c == d
           end
           """)
  end

  test "still fires when condition is not provably boolean, even with boolean else" do
    # no_if_true_false requires a provably-boolean condition, so it stays silent
    # here — only the negate-and-swap rewrite applies.
    assert flagged?(PreferNegateIfTrueFalse, """
           if some_call(x) do
             false
           else
             a == b
           end
           """)
  end
end
