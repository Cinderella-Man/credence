defmodule Credence.Syntax.CloseUnclosedDocHeredocFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.CloseUnclosedDocHeredoc

  defp analyze(code), do: CloseUnclosedDocHeredoc.analyze(code)
  defp fix(code), do: CloseUnclosedDocHeredoc.fix(code)

  test "fixes unclosed @doc heredoc by inserting closing quotes" do
    input = """
    defmodule Solution do
      @doc \"""
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Solution do
      @doc \"""
    #{close}
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes unclosed @doc heredoc with blank lines before def" do
    input = """
    defmodule Solution do
      @doc \"""

      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    close = "  \"\"\""

    expected = """
    defmodule Solution do
      @doc \"""

    #{close}
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "does not modify properly closed @doc heredoc" do
    code = """
    defmodule Solution do
      @doc \"\"\"
      Finds the min and max.
      \"\"\"
      def find_min_max(list) do
        Enum.min_max(list)
      end
    end
    """

    confirm_fix(fix(code), code)
  end

  test "fixed output no longer flags" do
    assert analyze(
             fix("""
             defmodule Solution do
               @doc \"""
               def find_min_max(list) do
                 Enum.min_max(list)
               end
             end
             """)
           ) == []
  end

  test "closes every unclosed @doc heredoc in a module" do
    input = """
    defmodule Solution do
      @doc \"""
      def a(x) do
        x
      end

      @doc \"""
      def b(x) do
        x
      end
    end
    """

    expected = """
    defmodule Solution do
      @doc \"""
      \"""
      def a(x) do
        x
      end

      @doc \"""
      \"""
      def b(x) do
        x
      end
    end
    """

    confirm_fix(fix(input), expected)
    assert valid_syntax?(fix(input))
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(
             fix("""
             defmodule Solution do
               @doc \"""
               def find_min_max(list) do
                 Enum.min_max(list)
               end
             end
             """)
           )
  end
end
