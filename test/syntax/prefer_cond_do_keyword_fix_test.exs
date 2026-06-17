defmodule Credence.Syntax.PreferCondDoKeywordFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.PreferCondDoKeyword

  defp analyze(code), do: PreferCondDoKeyword.analyze(code)
  defp fix(code), do: PreferCondDoKeyword.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Solution do
      def find_min(list) do
        cond ->
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      def find_min(list) do
        cond do
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
                 end
               end
             end
             """)
           ) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               def find_min(list) do
                 cond ->
                   list == [] -> nil
                   true -> Enum.min(list)
                 end
               end
             end
             """)
           )
  end

  test "leaves a `cond ->` inside a docstring untouched when the file is broken elsewhere" do
    input = """
    defmodule Solution do
      @moduledoc \"\"\"
      Example: cond -> in other languages.
      \"\"\"
      def f(list) do
        Enum.map(list
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes the real `cond ->` while preserving a `cond ->` in a docstring" do
    input = """
    defmodule Solution do
      @moduledoc \"\"\"
      Like cond -> in other languages.
      \"\"\"
      def find_min(list) do
        cond ->
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    expected = """
    defmodule Solution do
      @moduledoc \"\"\"
      Like cond -> in other languages.
      \"\"\"
      def find_min(list) do
        cond do
          list == [] -> nil
          true -> Enum.min(list)
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end
end
