defmodule Credence.Semantic.NoOrInCasePatternFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoOrInCasePattern

  @msg "or is not allowed in patterns"

  defp fix(source, line \\ 1) do
    NoOrInCasePattern.fix(source, %{severity: :error, message: @msg, position: {line, 1}})
  end

  test "splits or pattern into separate clauses" do
    input = """
    defmodule Example do
      def classify(value) do
        case value do
          nil or "" -> :empty
          _ -> :present
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def classify(value) do
        case value do
          nil -> :empty
          "" -> :empty
          _ -> :present
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def classify(value) do
        case value do
          nil or "" -> :empty
          _ -> :present
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end

  test "end-to-end: the semantic pipeline resolves the real compile error" do
    input = """
    defmodule Example do
      def classify(value) do
        case value do
          nil or "" -> :empty
          _ -> :present
        end
      end
    end
    """

    expected = """
    defmodule Example do
      def classify(value) do
        case value do
          nil -> :empty
          "" -> :empty
          _ -> :present
        end
      end
    end
    """

    confirm_fix(Credence.Semantic.fix(input), expected)
  end

  test "repairs or patterns in function clauses and match expressions" do
    input = """
    defmodule NoOrFunctionAndMatchRegression do
      def classify(nil or ""), do: :empty
      def classify(_), do: :present

      def assert_empty(value) do
        (nil or "") = value
      end
    end
    """

    expected = """
    defmodule NoOrFunctionAndMatchRegression do
      def classify(nil), do: :empty
      def classify(""), do: :empty
      def classify(_), do: :present

      def assert_empty(value) do
        case value do
          nil = __or_pattern_value__ -> __or_pattern_value__
          "" = __or_pattern_value__ -> __or_pattern_value__
        end
      end
    end
    """

    emitted = fix(input)

    confirm_fix(emitted, expected)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "expands an or nested inside a case pattern" do
    input = """
    defmodule NoOrNestedCaseRegression do
      def second(value) do
        case value do
          {nil or "", x} -> x
        end
      end
    end
    """

    expected = """
    defmodule NoOrNestedCaseRegression do
      def second(value) do
        case value do
          {nil, x} -> x
          {"", x} -> x
        end
      end
    end
    """

    emitted = fix(input)

    confirm_fix(emitted, expected)

    assert Credence.RuleHelpers.compile_and_capture(emitted) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end

  test "does not rewrite case syntax inside quote" do
    input = """
    defmodule NoOrQuotedCaseRegression do
      def repair(value) do
        result =
          case value do
            nil or "" -> :empty
            _ -> :present
          end

        quoted =
          quote do
            case quoted_value do
              nil or "" -> :quoted
            end
          end

        {result, quoted}
      end
    end
    """

    expected = """
    defmodule NoOrQuotedCaseRegression do
      def repair(value) do
        result =
          case value do
            nil -> :empty
            "" -> :empty
            _ -> :present
          end

        quoted =
          quote do
            case quoted_value do
              nil or "" -> :quoted
            end
          end

        {result, quoted}
      end
    end
    """

    confirm_fix(fix(input), expected)

    assert Credence.RuleHelpers.compile_and_capture(fix(input)) ==
             Credence.RuleHelpers.compile_and_capture(expected)
  end
end
