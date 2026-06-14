defmodule Credence.Syntax.PreferListUpdateAtFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferListUpdateAt

  defp analyze(code), do: PreferListUpdateAt.analyze(code)
  defp fix(code), do: PreferListUpdateAt.fix(code)

  test "fixes List.update_elem to List.update_at" do
    input = "List.update_elem(my_list, 0, new_value)"

    expected = "List.update_at(my_list, 0, fn _ -> new_value end)"

    confirm_fix(fix(input), expected)
  end

  test "fixes List.update_elem inside a module" do
    input = """
    defmodule Demo do
      def fix_me(list, index, value) do
        List.update_elem(list, index, value)
      end
    end
    """

    expected = """
    defmodule Demo do
      def fix_me(list, index, value) do
        List.update_at(list, index, fn _ -> value end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("List.update_elem(my_list, 0, new_value)")) == []
  end

  test "fixed output is well-formed (parses)" do
    # the repaired source must be valid Elixir
    assert valid_syntax?(
             fix("""
             defmodule Demo do
               def fix_me(list, index, value) do
                 List.update_elem(list, index, value)
               end
             end
             """)
           )
  end
end
