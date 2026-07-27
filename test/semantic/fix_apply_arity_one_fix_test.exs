defmodule Credence.Semantic.FixApplyArityOneFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixApplyArityOne

  @msg "undefined function apply/1 (expected FixApplyArityOneExample to define such a function or for it to be imported, but none are available)"

  defp fix(source, message, line) do
    FixApplyArityOne.fix(source, %{severity: :error, message: message, position: {line, 1}})
  end

  test "fixes apply(func) to apply(func, [])" do
    input = """
    defmodule FixApplyArityOneExample do
      def call_clock(state) do
        current_time = apply(state.clock)
        current_time
      end
    end
    """

    expected = """
    defmodule FixApplyArityOneExample do
      def call_clock(state) do
        current_time = apply(state.clock, [])
        current_time
      end
    end
    """

    confirm_fix(fix(input, @msg, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FixApplyArityOneExample do
      def call_clock(state) do
        current_time = apply(state.clock)
        current_time
      end
    end
    """

    assert valid_syntax?(fix(input, @msg, 3))
  end
end
