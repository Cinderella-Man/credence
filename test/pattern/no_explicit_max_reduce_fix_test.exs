defmodule Credence.Pattern.NoExplicitMaxReduceFixTest do
  use ExUnit.Case

  alias Credence.Pattern.NoExplicitMaxReduce

  defp check(code) do
    ast = Sourceror.parse_string!(code)
    NoExplicitMaxReduce.check(ast, [])
  end

  defp fix(code) do
    Credence.RuleHelpers.apply_rule_fix(NoExplicitMaxReduce, code, [])
    |> Code.format_string!()
    |> IO.iodata_to_binary()
    |> Kernel.<>("\n")
  end

  describe "fix/2" do
    test "replaces max/2 reduce with Enum.max/1" do
      input = """
      Enum.reduce(list, 0, fn x, acc ->
        max(x, acc)
      end)
      """

      expected = """
      Enum.max(list)
      """

      assert fix(input) == expected
    end

    test "replaces if > reduce with Enum.max/1" do
      input = """
      Enum.reduce(list, 0, fn x, acc ->
        if x > acc do x else acc end
      end)
      """

      expected = """
      Enum.max(list)
      """

      assert fix(input) == expected
    end

    test "replaces if >= reduce with Enum.max/1" do
      input = """
      Enum.reduce(list, 0, fn x, acc ->
        if x >= acc do x else acc end
      end)
      """

      expected = """
      Enum.max(list)
      """

      assert fix(input) == expected
    end

    test "does not modify sum reductions" do
      code = """
      Enum.reduce(list, 0, fn x, acc ->
        acc + x
      end)
      """

      assert fix(code) == code
    end

    test "fixes multiple max reduces in one pass" do
      input = """
      defmodule MultiFix do
        def process(a, b) do
          x = Enum.reduce(a, 0, fn v, acc -> max(v, acc) end)
          y = Enum.reduce(b, 0, fn v, acc -> max(v, acc) end)
          {x, y}
        end
      end
      """

      expected = """
      defmodule MultiFix do
        def process(a, b) do
          x = Enum.max(a)
          y = Enum.max(b)
          {x, y}
        end
      end
      """

      assert fix(input) == expected
    end

    test "preserves surrounding code when fixing" do
      input = """
      defmodule Preserved do
        def run(list) do
          total = Enum.sum(list)
          biggest = Enum.reduce(list, 0, fn x, acc -> max(x, acc) end)
          {total, biggest}
        end
      end
      """

      expected = """
      defmodule Preserved do
        def run(list) do
          total = Enum.sum(list)
          biggest = Enum.max(list)
          {total, biggest}
        end
      end
      """

      assert fix(input) == expected
    end

    test "fixed code produces no issues" do
      code = """
      defmodule RoundTrip do
        def max_value(list) do
          Enum.reduce(list, 0, fn x, acc ->
            max(x, acc)
          end)
        end
      end
      """

      assert check(fix(code)) == []
    end
  end
end
