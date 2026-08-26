defmodule Credence.Semantic.NoUnreachableCaseClauseByTypeFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoUnreachableCaseClauseByType

  # Real message captured from `Code.with_diagnostics` on Elixir 1.20 for a
  # bare `:dt ->` clause matched against `DateTime.compare/2`.
  @message """
  the following clause will never match:

      :dt ->

  because it attempts to match on the result of:

      DateTime.compare(a, b)

  which has type:

      dynamic(:eq or :gt or :lt)
  """

  defp fix(source, line, message \\ @message) do
    NoUnreachableCaseClauseByType.fix(source, %{
      severity: :warning,
      message: message,
      position: line
    })
  end

  @buggy_source """
  defmodule CredenceUnreachableCaseFixRepro do
    def sort_order(a, b) do
      case DateTime.compare(a, b) do
        :lt -> :asc
        :gt -> :desc
        :eq -> :same
        :dt -> :unknown
      end
    end
  end
  """

  test "removes the unreachable :dt clause" do
    expected = """
    defmodule CredenceUnreachableCaseFixRepro do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(@buggy_source, 7), expected)
  end

  test "fixed output is well-formed and no longer warns" do
    assert valid_syntax?(fix(@buggy_source, 7))

    {:ok, diags} = Credence.RuleHelpers.compile_and_capture(fix(@buggy_source, 7))
    refute Enum.any?(diags, &NoUnreachableCaseClauseByType.match?/1)
  end

  test "the semantic phase applies the fix end to end" do
    expected = """
    defmodule CredenceUnreachableCaseFixRepro do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(@buggy_source), expected)
  end

  test "removes a dead clause that is not the last one" do
    input = """
    defmodule CredenceUnreachableCaseMiddle do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :dt -> :unknown
          :gt -> :desc
          :eq -> :same
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCaseMiddle do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input, 5), expected)
  end

  test "removes a dead clause whose body spans several lines" do
    input = """
    defmodule CredenceUnreachableCaseMultiline do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :dt ->
            _ignored = :side
            :unknown
          :eq -> :same
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCaseMultiline do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input, 5), expected)
  end

  test "does not delete a dead clause whose body expands a macro" do
    input = """
    defmodule CredenceUnreachableCaseCompileEffect do
      defmacrop explode do
        raise "unreachable macro expanded"
      end

      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :eq -> :same
          :dt -> explode()
        end
      end
    end
    """

    emitted = fix(input, 9)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(input)

    confirm_fix(emitted, input)
  end

  test "keeps a live clause with the same atom in another case" do
    input = """
    defmodule CredenceUnreachableCaseOtherCase do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
          :dt -> :unknown
        end
      end

      def label(kind) do
        case kind do
          :dt -> :datetime
          _ -> :other
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCaseOtherCase do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
        end
      end

      def label(kind) do
        case kind do
          :dt -> :datetime
          _ -> :other
        end
      end
    end
    """

    confirm_fix(fix(input, 7), expected)
  end

  test "removes a dead clause that comes first" do
    input = """
    defmodule CredenceUnreachableCaseFirst do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :dt -> :unknown
          :eq -> :same
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCaseFirst do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input, 4), expected)
  end

  test "removes a dead clause whose body contains a nested case on the same atom" do
    input = """
    defmodule CredenceUnreachableCaseNested do
      def sort_order(a, b, c) do
        case DateTime.compare(a, b) do
          :eq -> :same
          :dt ->
            case c do
              :dt -> 9
              _ -> 0
            end
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCaseNested do
      def sort_order(a, b, c) do
        case DateTime.compare(a, b) do
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input, 5), expected)
  end

  test "keeps the comments attached to the surviving clauses" do
    input = """
    defmodule CredenceUnreachableCaseComments do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          # ascending
          :lt -> :asc
          # hallucinated
          :dt -> :unknown
          # equal
          :eq -> :same
        end
      end
    end
    """

    expected = """
    defmodule CredenceUnreachableCaseComments do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          # ascending
          :lt -> :asc
          # equal
          :eq -> :same
        end
      end
    end
    """

    confirm_fix(fix(input, 7), expected)
  end

  test "leaves the source alone when the flagged line carries a different clause" do
    confirm_fix(fix(@buggy_source, 4), @buggy_source)
  end

  test "leaves the source alone when deleting would empty the case" do
    input = """
    defmodule CredenceUnreachableCaseSoleClause do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :dt -> :unknown
        end
      end
    end
    """

    confirm_fix(fix(input, 4), input)
  end

  test "leaves the source alone when two case expressions share the flagged line" do
    input = """
    defmodule CredenceUnreachableCaseAmbiguous do
      def f(a, b, c, d) do
        {(case DateTime.compare(a, b) do :eq -> 1; :dt -> 2 end), (case c do :eq -> 1; :dt -> 2 end), d}
      end
    end
    """

    confirm_fix(fix(input, 3), input)
  end

  test "leaves the source alone for a guarded dead clause" do
    input = """
    defmodule CredenceUnreachableCaseGuarded do
      def sort_order(a, b, x) do
        case DateTime.compare(a, b) do
          :lt -> :asc
          :gt -> :desc
          :eq -> :same
          :dt when x > 0 -> :unknown
        end
      end
    end
    """

    guarded = String.replace(@message, ":dt ->", ":dt when x > 0 ->")
    confirm_fix(fix(input, 7, guarded), input)
  end

  test "leaves a dead fn clause alone (only case clauses are deleted)" do
    input = """
    defmodule CredenceUnreachableCaseFn do
      def sort_order(a, b) do
        fun = fn
          :lt -> :asc
          :dt -> :unknown
        end

        fun.(DateTime.compare(a, b))
      end
    end
    """

    confirm_fix(fix(input, 5), input)
  end

  test "leaves the source alone when the message quotes no bare atom clause" do
    bad_message = """
    the following clause will never match:

        something weird

    because it attempts to match on the result of:

        foo

    which has type:

        bar
    """

    confirm_fix(fix(@buggy_source, 7, bad_message), @buggy_source)
  end

  test "leaves the source alone when the source does not parse" do
    input = """
    defmodule CredenceUnreachableCaseBroken do
      def sort_order(a, b) do
        case DateTime.compare(a, b) do
          :dt -> :unknown
    """

    confirm_fix(fix(input, 4), input)
  end

  test "leaves the source alone when the diagnostic has no usable position" do
    confirm_fix(fix(@buggy_source, nil), @buggy_source)
  end
end
