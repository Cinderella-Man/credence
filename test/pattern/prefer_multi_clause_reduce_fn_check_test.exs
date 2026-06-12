defmodule Credence.Pattern.PreferMultiClauseReduceFnCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferMultiClauseReduceFn

  test "flags Enum.reduce with nested if/else" do
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

  test "leaves multi-clause reduce alone" do
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, {nil, 0}, fn
             element, {candidate, 0} -> {element, 1}
             element, {candidate, count} when element == candidate -> {candidate, count + 1}
             _element, {candidate, count} -> {candidate, count - 1}
           end)
           """)
  end

  test "leaves reduce without if/else alone" do
    assert clean?(PreferMultiClauseReduceFn, """
           Enum.reduce(list, 0, fn x, acc -> x + acc end)
           """)
  end

  test "leaves non-reduce code alone" do
    assert clean?(PreferMultiClauseReduceFn, """
           if count == 0 do
             {element, 1}
           else
             {element, count - 1}
           end
           """)
  end

  test "leaves single-level if/else in reduce alone" do
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
end
