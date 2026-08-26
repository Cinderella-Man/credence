defmodule Credence.Semantic.NoStreamDataIntegerTwoArgsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1, compiles?: 1]

  alias Credence.Semantic.NoStreamDataIntegerTwoArgs

  @message "undefined function integer/2 (expected M to define such a function or for it to be imported, but none are available)"

  defp fix(source, position) do
    NoStreamDataIntegerTwoArgs.fix(source, %{
      severity: :error,
      message: @message,
      position: position
    })
  end

  test "rewrites the flagged call's comma into a range" do
    input = """
    defmodule CredenceIntegerTwoArgsFlagship do
      import StreamData

      def account_program do
        bind(integer(0, 10), fn n ->
          deposit = {:deposit, integer(1, 1000)}
          {:withdraw, integer(1, n)}
          constant(deposit)
        end)
      end
    end
    """

    # Only the call at the flagged line/column moves; the other two wait for
    # their own diagnostics.
    expected = """
    defmodule CredenceIntegerTwoArgsFlagship do
      import StreamData

      def account_program do
        bind(integer(0..10), fn n ->
          deposit = {:deposit, integer(1, 1000)}
          {:withdraw, integer(1, n)}
          constant(deposit)
        end)
      end
    end
    """

    confirm_fix(fix(input, {5, 10}), expected)
  end

  test "the phase fixes every flagged call and the result compiles" do
    input = """
    defmodule CredenceIntegerTwoArgsPhase do
      import StreamData

      def account_program do
        bind(integer(0, 10), fn n ->
          deposit = {:deposit, integer(1, 1000)}
          {:withdraw, integer(1, n)}
          constant(deposit)
        end)
      end
    end
    """

    expected = """
    defmodule CredenceIntegerTwoArgsPhase do
      import StreamData

      def account_program do
        bind(integer(0..10), fn n ->
          deposit = {:deposit, integer(1..1000)}
          {:withdraw, integer(1..n)}
          constant(deposit)
        end)
      end
    end
    """

    fixed = Credence.Semantic.fix(input)
    confirm_fix(fixed, expected)
    assert compiles?(fixed)
  end

  test "rewrites a negated integer literal" do
    input = """
    defmodule CredenceIntegerTwoArgsNegative do
      import StreamData

      def offsets, do: integer(-5, 5)
    end
    """

    expected = """
    defmodule CredenceIntegerTwoArgsNegative do
      import StreamData

      def offsets, do: integer(-5..5)
    end
    """

    confirm_fix(fix(input, {4, 20}), expected)
    assert compiles?(fix(input, {4, 20}))
  end

  test "rewrites a call whose arguments straddle lines" do
    input = """
    defmodule CredenceIntegerTwoArgsMultiline do
      import StreamData

      def gen do
        integer(
          0,
          10
        )
      end
    end
    """

    expected = """
    defmodule CredenceIntegerTwoArgsMultiline do
      import StreamData

      def gen do
        integer(
          0..10
        )
      end
    end
    """

    confirm_fix(fix(input, {5, 5}), expected)
    assert valid_syntax?(fix(input, {5, 5}))
  end

  test "rewrites a call under use ExUnitProperties, which imports StreamData" do
    input = """
    defmodule CredenceIntegerTwoArgsProperty do
      use ExUnitProperties

      def gen, do: integer(1, 100)
    end
    """

    expected = """
    defmodule CredenceIntegerTwoArgsProperty do
      use ExUnitProperties

      def gen, do: integer(1..100)
    end
    """

    confirm_fix(fix(input, {4, 16}), expected)
  end

  test "rewrites only the flagged call, leaving a same-named definition alone" do
    input = """
    defmodule CredenceIntegerTwoArgsCaller do
      import StreamData

      def gen, do: integer(0, 10)
    end

    defmodule CredenceIntegerTwoArgsHelper do
      def integer(min, max), do: {min, max}
    end
    """

    expected = """
    defmodule CredenceIntegerTwoArgsCaller do
      import StreamData

      def gen, do: integer(0..10)
    end

    defmodule CredenceIntegerTwoArgsHelper do
      def integer(min, max), do: {min, max}
    end
    """

    confirm_fix(fix(input, {4, 16}), expected)
  end

  test "leaves a call in another function outside an import's lexical scope alone" do
    input = """
    defmodule CredenceIntegerTwoArgsFunctionScope do
      def imported do
        import StreamData
        :ok
      end
      def broken, do: integer(0, 10)
    end
    """

    confirm_fix(fix(input, {6, 19}), input)
  end

  test "leaves a call outside a branch-local import alone" do
    input = """
    defmodule CredenceIntegerTwoArgsBranchScope do
      def gen(condition) do
        if condition do
          import StreamData
          constant(:ok)
        end

        integer(0, 10)
      end
    end
    """

    confirm_fix(fix(input, {8, 5}), input)
  end

  test "leaves a call alone when only excludes integer/1 from the import" do
    input = """
    defmodule CredenceIntegerTwoArgsOnlyOption do
      import StreamData, only: [constant: 1]

      def broken, do: integer(0, 10)
    end
    """

    confirm_fix(fix(input, {4, 19}), input)
  end

  test "leaves a call alone when except excludes integer/1 from the import" do
    input = """
    defmodule CredenceIntegerTwoArgsExceptOption do
      import StreamData, except: [integer: 1]

      def broken, do: integer(0, 10)
    end
    """

    confirm_fix(fix(input, {4, 19}), input)
  end

  test "rewrites when integer/1 is explicitly imported in the function scope" do
    input = """
    defmodule CredenceIntegerTwoArgsScopedOnlyOption do
      def gen do
        import StreamData, only: [integer: 1]
        integer(0, 10)
      end
    end
    """

    expected = """
    defmodule CredenceIntegerTwoArgsScopedOnlyOption do
      def gen do
        import StreamData, only: [integer: 1]
        integer(0..10)
      end
    end
    """

    confirm_fix(fix(input, {4, 5}), expected)
  end

  #
  # No-ops — every case the check also declines to report.

  test "leaves the call alone when the file does not import StreamData" do
    input = """
    defmodule CredenceIntegerTwoArgsNoImport do
      def gen, do: integer(0, 10)
    end
    """

    confirm_fix(fix(input, {2, 16}), input)
  end

  test "leaves a sibling module that never imported StreamData alone" do
    input = """
    defmodule CredenceIntegerTwoArgsImporter do
      import StreamData

      def gen, do: integer(0, 10)
    end

    defmodule CredenceIntegerTwoArgsSibling do
      def gen, do: integer(0, 10)
    end
    """

    # The compiler stops at the first module, so line 9 is the diagnostic the
    # phase's second pass sees once the importer's own call is repaired.
    confirm_fix(fix(input, {9, 16}), input)

    importer_fixed = """
    defmodule CredenceIntegerTwoArgsImporter do
      import StreamData

      def gen, do: integer(0..10)
    end

    defmodule CredenceIntegerTwoArgsSibling do
      def gen, do: integer(0, 10)
    end
    """

    confirm_fix(fix(input, {4, 16}), importer_fixed)
  end

  test "leaves a call above its module's import alone" do
    input = """
    defmodule CredenceIntegerTwoArgsLate do
      def gen, do: integer(0, 10)

      import StreamData
    end
    """

    confirm_fix(fix(input, {2, 16}), input)
  end

  test "leaves a piped argument alone (.. would re-associate it)" do
    input = """
    defmodule CredenceIntegerTwoArgsPipe do
      import StreamData

      def gen(x, y), do: integer(x |> abs(), y)
    end
    """

    confirm_fix(fix(input, {4, 22}), input)
  end

  test "leaves a comparison argument alone (.. binds tighter than <)" do
    input = """
    defmodule CredenceIntegerTwoArgsCompare do
      import StreamData

      def gen(a, b), do: integer(a < b, b)
    end
    """

    confirm_fix(fix(input, {4, 22}), input)
  end

  test "leaves an arithmetic argument alone (outside the proven-safe set)" do
    input = """
    defmodule CredenceIntegerTwoArgsArithmetic do
      import StreamData

      def gen(n), do: integer(0, n - 1)
    end
    """

    confirm_fix(fix(input, {4, 19}), input)
  end

  test "leaves a call argument alone (outside the proven-safe set)" do
    input = """
    defmodule CredenceIntegerTwoArgsCallArg do
      import StreamData

      def gen(list), do: integer(0, length(list))
    end
    """

    confirm_fix(fix(input, {4, 22}), input)
  end

  test "leaves a comment between the arguments intact" do
    input =
      """
      defmodule CredenceIntegerTwoArgsComment do
        import StreamData

        def gen do
          integer(0,
            # upper bound
            10)
        end
      end
      """

    confirm_fix(fix(input, {5, 5}), input)
  end

  test "leaves the source alone when the flagged position holds no such call" do
    input = """
    defmodule CredenceIntegerTwoArgsElsewhere do
      import StreamData

      def gen, do: integer(0, 10)
    end
    """

    confirm_fix(fix(input, {2, 3}), input)
  end

  test "leaves other arities of integer alone" do
    input = """
    defmodule CredenceIntegerTwoArgsArity do
      import StreamData

      def gen, do: integer(0, 10, 2)
    end
    """

    confirm_fix(fix(input, {4, 16}), input)
  end

  test "leaves unparseable source alone" do
    input = """
    defmodule CredenceIntegerTwoArgsBroken do
      import StreamData

      def gen, do: integer(0, 10
    end
    """

    confirm_fix(fix(input, {4, 16}), input)
  end

  test "leaves unrelated source alone" do
    input = """
    defmodule CredenceIntegerTwoArgsUnrelated do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, {2, 3}), input)
  end
end
