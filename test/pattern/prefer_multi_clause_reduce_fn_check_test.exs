defmodule Credence.Pattern.PreferMultiClauseReduceFnCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMultiClauseReduceFn

  test "flags nested if/else whose conditions are plain comparisons" do
    assert flagged?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
             if count == 0 do
               {element, 1}
             else
               if element == candidate do
                 {candidate, count + 1}
               else
                 {candidate, count - 1}
               end
             end
           end)
           """)
  end

  test "leaves already multi-clause reduce alone" do
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {nil, 0}, fn
             element, {candidate, count} when count == 0 -> {element, 1}
             element, {candidate, count} when element == candidate -> {candidate, count + 1}
             _element, {candidate, count} -> {candidate, count - 1}
           end)
           """)
  end

  test "leaves reduce without if/else alone" do
    assert clean?(PreferMultiClauseReduceFn, "Enum.reduce(list, 0, fn x, acc -> x + acc end)")
  end

  test "leaves non-fn code alone" do
    assert clean?(PreferMultiClauseReduceFn, """
           if count == 0 do
             {element, 1}
           else
             {element, count - 1}
           end
           """)
  end

  test "leaves single-level if/else alone" do
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {0, 0}, fn x, {sum, count} ->
             if x > 0 do
               {sum + x, count + 1}
             else
               {sum, count}
             end
           end)
           """)
  end

  # ── deliberately not flagged: no safe same-answer guard rewrite exists ──

  test "no issue when the innermost if has no else (no catch-all to map to)" do
    # Turning this into a multi-clause fn would make the last clause a catch-all
    # that returns the inner branch, where the original returns nil instead.
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
             if count == 0 do
               {element, 1}
             else
               if element == candidate do
                 {candidate, count + 1}
               end
             end
           end)
           """)
  end

  test "no issue when a condition has a computed leaf (guard would swallow errors)" do
    # `count + 1 == 0` in a guard would silently skip the clause if `count` were
    # not a number, instead of raising as the original `if` does.
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
             if count + 1 == 0 do
               {element, 1}
             else
               if element == candidate do
                 {candidate, count + 1}
               else
                 {candidate, count - 1}
               end
             end
           end)
           """)
  end

  test "no issue when a condition is not a comparison" do
    # `is_nil(candidate)` would be a valid guard, but a non-comparison condition
    # such as a plain function call is left alone to keep the safe core narrow.
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {nil, 0}, fn element, {candidate, count} ->
             if valid?(candidate) do
               {element, 1}
             else
               if element == candidate do
                 {candidate, count + 1}
               else
                 {candidate, count - 1}
               end
             end
           end)
           """)
  end
end
