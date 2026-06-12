defmodule Credence.Syntax.PreferListUpdateAtAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.PreferListUpdateAt

  defp analyze(code), do: PreferListUpdateAt.analyze(code)

  test "flags List.update_elem/3" do
    assert [%Issue{rule: :prefer_list_update_at}] =
             analyze("""
             List.update_elem(my_list, 0, new_value)
             """)
  end

  test "flags List.update_elem/3 inside a module" do
    assert [%Issue{rule: :prefer_list_update_at}] =
             analyze("""
             defmodule Demo do
               def fix_me(list, index, value) do
                 List.update_elem(list, index, value)
               end
             end
             """)
  end

  test "leaves List.update_at/3 alone" do
    assert analyze("""
           List.update_at(my_list, 0, fn _ -> new_value end)
           """) == []
  end

  test "leaves unrelated code alone" do
    assert analyze("""
           Enum.map(list, &(&1 + 1))
           """) == []
  end
end
