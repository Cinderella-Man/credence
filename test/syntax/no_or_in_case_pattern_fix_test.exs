defmodule Credence.Syntax.NoOrInCasePatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoOrInCasePattern

  defp analyze(code), do: NoOrInCasePattern.analyze(code)
  defp fix(code), do: NoOrInCasePattern.fix(code)

  test "fixes the syntax error" do
    input = """
    defmodule Example do
      def match(val) do
        case val do
          nil or "" -> :empty
          _ -> :ok
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def match(val) do
        case val do
          nil -> :empty
          "" -> :empty
          _ -> :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    assert analyze(fix("""
           defmodule Example do
             def match(val) do
               case val do
                 nil or "" -> :empty
                 _ -> :ok
               end
             end
           end
           """)) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule Example do
             def match(val) do
               case val do
                 nil or "" -> :empty
                 _ -> :ok
               end
             end
           end
           """))
  end

  test "leaves already-clean source unchanged" do
    input = """
    defmodule Example do
      def match(val) do
        case val do
          nil -> :empty
          "" -> :empty
          _ -> :ok
        end
      end
    end
    """

    confirm_fix(fix(input), input)
  end

  test "fixes nested or" do
    input = """
    defmodule Example do
      def match(val) do
        case val do
          nil or "" or false -> :empty
          _ -> :ok
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def match(val) do
        case val do
          nil -> :empty
          "" -> :empty
          false -> :empty
          _ -> :ok
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end
end
