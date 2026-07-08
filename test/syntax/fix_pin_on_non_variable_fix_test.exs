defmodule Credence.Syntax.FixPinOnNonVariableFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.FixPinOnNonVariable

  defp analyze(code), do: FixPinOnNonVariable.analyze(code)
  defp fix(code), do: FixPinOnNonVariable.fix(code)

  test "fixes pin on tuple in list pattern" do
    input = """
    case value do
      [^{key}, rest] -> rest
      _ -> nil
    end
    """

    expected = """
    case value do
      [{key}, rest] -> rest
      _ -> nil
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixed output no longer flags" do
    source = """
    case value do
      [^{key}, rest] -> rest
      _ -> nil
    end
    """

    assert analyze(fix(source)) == []
  end

  test "fixed output is well-formed (parses)" do
    source = """
    case value do
      [^{key}, rest] -> rest
      _ -> nil
    end
    """

    assert valid_syntax?(fix(source))
  end

  test "leaves valid code unchanged" do
    source = """
    case value do
      [{key}, rest] -> rest
      _ -> nil
    end
    """

    confirm_fix(fix(source), source)
  end
end
