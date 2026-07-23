defmodule Credence.Semantic.FixInvalidListTypespecSyntaxFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, compiles?: 1, valid_syntax?: 1]

  alias Credence.Semantic.FixInvalidListTypespecSyntax

  @message "credence_check.ex:6: unexpected list in typespec: [integer(), integer()]"

  defp fix(source, line) do
    FixInvalidListTypespecSyntax.fix(source, %{
      severity: :error,
      message: @message,
      position: {line, 1}
    })
  end

  test "collapses identical element types to a single list element type" do
    input = """
    defmodule SolutionA do
      @spec has_path(num_nodes :: non_neg_integer(), edges :: list([integer(), integer()]), source :: integer(), destination :: integer()) :: boolean()
      def has_path(num_nodes, edges, source, destination) do
        true
      end
    end
    """

    expected = """
    defmodule SolutionA do
      @spec has_path(num_nodes :: non_neg_integer(), edges :: list([integer()]), source :: integer(), destination :: integer()) :: boolean()
      def has_path(num_nodes, edges, source, destination) do
        true
      end
    end
    """

    confirm_fix(fix(input, 2), expected)
  end

  test "fixed output compiles (the diagnostic is resolved)" do
    input = """
    defmodule SolutionB do
      @spec has_path(edges :: list([integer(), integer()])) :: boolean()
      def has_path(edges) do
        true
      end
    end
    """

    refute compiles?(input)
    assert compiles?(fix(input, 2))
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule SolutionL do
      @spec has_path(edges :: list([integer(), integer()])) :: boolean()
      def has_path(edges) do
        true
      end
    end
    """

    assert valid_syntax?(fix(input, 2))
  end

  test "distinct element types become a union" do
    input = """
    defmodule SolutionC do
      @spec pairs(list([integer(), atom(), binary()])) :: boolean()
      def pairs(items), do: true
    end
    """

    expected = """
    defmodule SolutionC do
      @spec pairs(list([integer() | atom() | binary()])) :: boolean()
      def pairs(items), do: true
    end
    """

    confirm_fix(fix(input, 2), expected)
    assert compiles?(fix(input, 2))
  end

  test "commas nested inside tuples and calls are not split" do
    input = """
    defmodule SolutionD do
      @spec f(list([{integer(), atom()}, binary()])) :: boolean()
      def f(x), do: true
    end
    """

    expected = """
    defmodule SolutionD do
      @spec f(list([{integer(), atom()} | binary()])) :: boolean()
      def f(x), do: true
    end
    """

    confirm_fix(fix(input, 2), expected)
    assert compiles?(fix(input, 2))
  end

  test "fixes multiple list([...]) occurrences on the flagged line" do
    input = """
    defmodule SolutionE do
      @spec f(list([integer(), integer()]), list([atom(), binary()])) :: boolean()
      def f(a, b), do: true
    end
    """

    expected = """
    defmodule SolutionE do
      @spec f(list([integer()]), list([atom() | binary()])) :: boolean()
      def f(a, b), do: true
    end
    """

    confirm_fix(fix(input, 2), expected)
    assert compiles?(fix(input, 2))
  end

  test "fixes a list([...]) nested inside another list([...])" do
    input = """
    defmodule SolutionF do
      @spec f(list([list([integer(), integer()]), atom()])) :: boolean()
      def f(x), do: true
    end
    """

    expected = """
    defmodule SolutionF do
      @spec f(list([list([integer()]) | atom()])) :: boolean()
      def f(x), do: true
    end
    """

    confirm_fix(fix(input, 2), expected)
    assert compiles?(fix(input, 2))
  end

  test "leaves valid single-element list([type]) untouched" do
    source = """
    defmodule SolutionG do
      @spec f(list([integer()])) :: boolean()
      def f(x), do: true
    end
    """

    confirm_fix(fix(source, 2), source)
  end

  test "leaves valid non-empty list form list([type, ...]) untouched" do
    source = """
    defmodule SolutionH do
      @spec f(list([integer(), ...])) :: boolean()
      def f(x), do: true
    end
    """

    confirm_fix(fix(source, 2), source)
  end

  test "leaves valid keyword list form list([key: type]) untouched" do
    source = """
    defmodule SolutionI do
      @spec f(list([foo: integer(), bar: atom()])) :: boolean()
      def f(x), do: true
    end
    """

    confirm_fix(fix(source, 2), source)
  end

  test "does not rewrite my_list([...]) or M.list([...]) calls" do
    source = """
    defmodule SolutionJ do
      @spec f(my_list([integer(), integer()]), M.list([integer(), atom()])) :: boolean()
      def f(a, b), do: true
    end
    """

    confirm_fix(fix(source, 2), source)
  end

  test "returns source unchanged when line has no list([)" do
    source = """
    defmodule SolutionK do
      @spec foo(x :: integer()) :: boolean()
      def foo(x), do: true
    end
    """

    confirm_fix(fix(source, 2), source)
  end

  test "returns source unchanged when position is nil" do
    source = "some code"
    bad_diag = %{severity: :error, message: @message, position: nil}
    confirm_fix(FixInvalidListTypespecSyntax.fix(source, bad_diag), source)
  end
end
