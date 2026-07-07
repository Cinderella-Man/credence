defmodule Credence.Syntax.NoCaptureAsIdentityFunctionFixTest do
  use ExUnit.Case

  import Credence.RuleCase, only: [confirm_fix: 2, valid_syntax?: 1]

  alias Credence.Syntax.NoCaptureAsIdentityFunction

  defp analyze(code), do: NoCaptureAsIdentityFunction.analyze(code)
  defp fix(code), do: NoCaptureAsIdentityFunction.fix(code)

  test "replaces &variable with fn _ -> variable end" do
    input = "Map.update!(m, :key, &new_value)"

    expected = "Map.update!(m, :key, fn _ -> new_value end)"

    confirm_fix(fix(input), expected)
  end

  test "fixes &variable inside a module" do
    input = """
    defmodule CaptureAsIdentity do
      def update_list(list, new_value) do
        Map.update!(%{key: list}, :key, &new_value)
      end
    end
    """

    expected = """
    defmodule CaptureAsIdentity do
      def update_list(list, new_value) do
        Map.update!(%{key: list}, :key, fn _ -> new_value end)
      end
    end
    """

    confirm_fix(fix(input), expected)
  end

  test "fixes multiple &variable on different lines" do
    input = """
    Map.update!(m, :k, &val1)
    Map.update!(m, :k2, &val2)
    """

    expected = """
    Map.update!(m, :k, fn _ -> val1 end)
    Map.update!(m, :k2, fn _ -> val2 end)
    """

    confirm_fix(fix(input), expected)
  end

  test "fix clears the analyze flag (fixpoint)" do
    assert analyze(fix("Map.update!(m, :key, &new_value)")) == []
  end

  test "fixed output is well-formed (parses)" do
    assert valid_syntax?(fix("""
           defmodule CaptureAsIdentity do
             def update_list(list, new_value) do
               Map.update!(%{key: list}, :key, &new_value)
             end
           end
           """))
  end

  test "leaves valid capture &1 untouched" do
    source = "Enum.filter(list, &(&1 > 0))"

    confirm_fix(fix(source), source)
  end

  test "leaves valid function reference untouched" do
    source = "Enum.map(list, &String.length/1)"

    confirm_fix(fix(source), source)
  end

  test "leaves valid capture body untouched" do
    source = "Enum.map(list, &to_string(&1))"

    confirm_fix(fix(source), source)
  end

  test "leaves a comment line untouched" do
    source = "# Map.update!(m, :key, &new_value)"

    confirm_fix(fix(source), source)
  end
end
