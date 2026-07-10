defmodule Credence.Semantic.FixBitwiseInfixOperatorFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Semantic.FixBitwiseInfixOperator

  @or_msg """
  invalid syntax found on credence_check.ex:190:45:
       error: syntax error before: '>'
       │
   190 │     do_secure_compare(ta, tb, acc ||| (ha <-> hb))
       │                                             ^
       │
       └─ credence_check.ex:190:45
  """

  @xor_msg """
  invalid syntax found on example.ex:3:20:
       error: syntax error before: '^'
       │
     3 │     diff = a ^^^ b
       │                    ^
       │
       └─ example.ex:3:20
  """

  defp fix(source, message, line \\ 1) do
    FixBitwiseInfixOperator.fix(source, %{
      severity: :error,
      message: message,
      position: {line, 1}
    })
  end

  @or_input """
  defmodule Test do
    def combine(a, b) do
      a ||| b
    end
  end
  """

  @or_expected """
  defmodule Test do
    def combine(a, b) do
      Bitwise.bor(a, b)
    end
  end
  """

  @xor_input """
  defmodule Test do
    def diff(a, b) do
      a ^^^ b
    end
  end
  """

  @xor_expected """
  defmodule Test do
    def diff(a, b) do
      Bitwise.bxor(a, b)
    end
  end
  """

  @mixed_input """
  defmodule Test do
    def xor_compare(a, b, acc) do
      diff = a ^^^ b
      acc ||| diff
    end
  end
  """

  @mixed_expected """
  defmodule Test do
    def xor_compare(a, b, acc) do
      diff = Bitwise.bxor(a, b)
      Bitwise.bor(acc, diff)
    end
  end
  """

  test "fixes ||| to Bitwise.bor" do
    confirm_fix(fix(@or_input, @or_msg, 3), @or_expected)
  end

  test "fixes ^^^ to Bitwise.bxor" do
    confirm_fix(fix(@xor_input, @xor_msg, 3), @xor_expected)
  end

  test "fixes mixed ||| and ^^^ operators" do
    confirm_fix(fix(@mixed_input, @or_msg, 3), @mixed_expected)
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix(@or_input, @or_msg, 3))
  end

  test "does not change source without bitwise operators" do
    input = """
    defmodule Test do
      def add(a, b), do: a + b
    end
    """

    confirm_fix(fix(input, @or_msg, 2), input)
  end
end
