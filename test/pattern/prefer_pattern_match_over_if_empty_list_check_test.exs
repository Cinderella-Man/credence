defmodule Credence.Pattern.PreferPatternMatchOverIfEmptyListCheckTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.PreferPatternMatchOverIfEmptyList

  test "flags the anti-pattern: if list == []" do
    assert flagged?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process(list) do
               if list == [] do
                 0
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "flags the anti-pattern: if [] == list (reversed)" do
    assert flagged?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process(list) do
               if [] == list do
                 0
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "leaves good code alone: pattern-matched empty list clause" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process([]), do: 0

             def process(list) do
               Enum.sum(list)
             end
           end
           """)
  end

  test "leaves good code alone: no empty list check" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process(list) do
               Enum.sum(list)
             end
           end
           """)
  end

  test "leaves good code alone: if with non-empty-list condition" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process(list) do
               if list == nil do
                 0
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "leaves good code alone: pattern match on other value" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process(list, target) do
               if list == target do
                 0
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "leaves good code alone: multi-param function" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def process(list, extra) do
               if list == [] do
                 extra
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "leaves good code alone: defp with non-empty-list check" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             defp process(list) do
               if length(list) == 0 do
                 0
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "flags guarded if Enum.empty?(list) when is_list(list)" do
    assert flagged?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def total(list) when is_list(list) do
               if Enum.empty?(list) do
                 :none
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end

  test "does NOT flag Enum.empty? WITHOUT an is_list guard (non-list enumerables diverge)" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def total(coll) do
               if Enum.empty?(coll) do
                 :none
               else
                 Enum.sum(coll)
               end
             end
           end
           """)
  end

  test "does NOT flag Enum.empty? under a compound guard that can exclude []" do
    assert clean?(PreferPatternMatchOverIfEmptyList, """
           defmodule M do
             def total(list) when is_list(list) and length(list) > 0 do
               if Enum.empty?(list) do
                 :none
               else
                 Enum.sum(list)
               end
             end
           end
           """)
  end
end
