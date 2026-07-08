defmodule Credence.Syntax.FixPinOnNonVariableAnalyzeTest do
  use ExUnit.Case

  alias Credence.Issue
  alias Credence.Syntax.FixPinOnNonVariable

  defp analyze(code), do: FixPinOnNonVariable.analyze(code)

  test "flags pin on tuple in list pattern" do
    source = """
    case value do
      [^{key}, rest] -> rest
      _ -> nil
    end
    """

    assert [%Issue{rule: :fix_pin_on_non_variable}] = analyze(source)
  end

  test "flags pin on multi-element tuple" do
    source = """
    case value do
      {^{a, b}} -> {a, b}
    end
    """

    assert [%Issue{rule: :fix_pin_on_non_variable}] = analyze(source)
  end

  test "leaves valid pin on variable alone" do
    source = """
    case value do
      [^key, rest] -> rest
      _ -> nil
    end
    """

    assert analyze(source) == []
  end

  test "leaves code without pin alone" do
    source = """
    case value do
      [{key}, rest] -> rest
      _ -> nil
    end
    """

    assert analyze(source) == []
  end
end
