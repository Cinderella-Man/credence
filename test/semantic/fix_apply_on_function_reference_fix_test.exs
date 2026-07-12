defmodule Credence.Semantic.FixApplyOnFunctionReferenceFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixApplyOnFunctionReference

  @match_msg "apply(:call, []) detected — use receiver.() instead"

  defp fix(source, message, line \\ 1) do
    FixApplyOnFunctionReference.fix(source, %{
      severity: :warning,
      message: message,
      position: {line, 1}
    })
  end

  test "fixes apply(:call, []) to dot-call" do
    input = """
    defmodule FixApplyOnFunctionReference do
      def get_now(state) do
        apply(state.clock, :call, [])
      end
    end
    """

    expected = """
    defmodule FixApplyOnFunctionReference do
      def get_now(state) do
        state.clock.()
      end
    end
    """

    confirm_fix(fix(input, @match_msg, 3), expected)
  end

  test "fixed output is well-formed (parses)" do
    input = """
    defmodule FixApplyOnFunctionReference do
      def get_now(state) do
        apply(state.clock, :call, [])
      end
    end
    """

    assert valid_syntax?(fix(input, @match_msg, 3))
  end

  test "leaves unrelated source unchanged" do
    input = """
    defmodule Unrelated do
      def hello, do: :world
    end
    """

    confirm_fix(fix(input, @match_msg), input)
  end
end
