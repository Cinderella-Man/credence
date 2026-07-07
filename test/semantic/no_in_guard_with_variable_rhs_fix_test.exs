defmodule Credence.Semantic.NoInGuardWithVariableRhsFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.NoInGuardWithVariableRhs

  @real_message "invalid right argument for operator \"in\", it expects a compile-time proper list or compile-time range on the right side when used in guard expressions, got: rest"

  defp fix(source, line \\ 1) do
    NoInGuardWithVariableRhs.fix(source, %{severity: :error, message: @real_message, position: {line, 1}})
  end

  test "fixes in-guard-with-variable-rhs by splitting clauses" do
    input = """
    defmodule Example do
      @spec pipe_row?(charlist()) :: boolean()
      def pipe_row?(parts) do
        case parts do
          [first | rest] when first == ?| or ?| in rest -> true
          _ -> false
        end
      end
    end
    """

    expected = """
    defmodule Example do
      @spec pipe_row?(charlist()) :: boolean()
      def pipe_row?(parts) do
        case parts do
          [first | rest] when first == ?| -> true
          [?| | _] -> true
          parts when is_list(parts) -> Enum.member?(parts, ?|)
          _ -> false
        end
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule Example do
      def pipe_row?(parts) do
        case parts do
          [first | rest] when first == ?| or ?| in rest -> true
          _ -> false
        end
      end
    end
    """

    assert valid_syntax?(fix(input))
  end
end
