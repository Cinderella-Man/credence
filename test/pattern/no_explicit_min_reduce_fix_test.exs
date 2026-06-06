defmodule Credence.Pattern.NoExplicitMinReduceFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoExplicitMinReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoExplicitMinReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoExplicitMinReduce, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix" do
    test "replaces min/2 reduce with Enum.min/1" do
      input = """
      Enum.reduce(list, :infinity, fn x, acc -> min(x, acc) end)
      """

      expected = """
      Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "replaces if < reduce with Enum.min/1" do
      input = """
      Enum.reduce(list, :infinity, fn x, acc ->
        if x < acc do x else acc end
      end)
      """

      expected = """
      Enum.min(list)
      """

      assert fix(input) == expected
    end

    test "does not modify non-min reductions" do
      code = """
      Enum.reduce(list, 0, fn x, acc -> acc + x end)
      """

      assert fix(code) == code
    end

    test "fixes multiple min reduces in one pass" do
      input = """
      defmodule M do
        def run(a, b) do
          x = Enum.reduce(a, :infinity, fn v, acc -> min(v, acc) end)
          y = Enum.reduce(b, :infinity, fn v, acc -> min(v, acc) end)
          {x, y}
        end
      end
      """

      expected = """
      defmodule M do
        def run(a, b) do
          x = Enum.min(a)
          y = Enum.min(b)
          {x, y}
        end
      end
      """

      assert fix(input) == expected
    end

    test "round-trip: fixed code produces no issues" do
      code = """
      Enum.reduce(list, :infinity, fn x, acc -> min(x, acc) end)
      """

      assert check(fix(code)) == []
    end
  end
end
