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

  # A correctly closed `@doc """` is off limits no matter what its first content
  # line looks like. The rule only ever sees source that does not parse, so a
  # file like this one reaches it whenever some *other* line has a syntax error —
  # and rewriting it would empty the doc, promote the documented example to real
  # code, and turn the doc's own closing `"""` into an opening one that swallows
  # the code below. What holds the line is the "is there a `\"""` further down?"
  # guard, so these two cases pin it directly.
  test "leaves a closed @doc heredoc alone when its first content line is a def example" do
    code = """
    defmodule Solution do
      @doc \"\"\"
      def example do
        :ok
      end
      \"\"\"
      def a, do: 1

      @doc \"\"\"
      Docs for b.
      \"\"\"
      def b, do: 2
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  test "leaves a closed @doc heredoc alone when its first content line starts with \"def\"" do
    code = """
    defmodule Solution do
      @doc \"\"\"
      defaults to 0 when the key is absent.
      \"\"\"
      def get(map, key), do: Map.get(map, key)
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # "def" as the first three letters of an English word is not a definition. The
  # rule exists to close a doc *before the next definition*; with no definition
  # below there is nothing to close before, and firing anyway empties the doc and
  # spills its prose into the module body.
  test "does not treat prose beginning with \"def\" as the next definition" do
    code = """
    defmodule Sample do
      def get(map, key), do: Map.get(map, key)

      @doc \"\"\"
      defaults to 0 when the key is absent.
    end
    """

    assert analyze(code) == []
    confirm_fix(fix(code), code)
  end

  # The same false match, but here the rewrite's output *parses*: the doc is
  # silently emptied and its body becomes live code, which no downstream progress
  # guard can see (a source that parses is never reverted).
  test "does not treat a `defaults = ...` binding as the next definition" do
    code = """
    defmodule Sample do
      @doc \"\"\"
      1 + 1

      defaults = %{a: 1}
    end
    """

    assert analyze(code) == []
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
