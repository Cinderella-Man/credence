defmodule Credence.Rule.DescriptiveNamesTest do
  use ExUnit.Case

  defp check(code) do
    {:ok, ast} = Code.string_to_quoted(code)
    Credence.Rule.DescriptiveNames.check(ast, [])
  end

  describe "DescriptiveNames" do
    test "passes when parameters are descriptive" do
      code = """
      defmodule GoodNames do
        def calculate(price, tax_rate), do: price * tax_rate
      end
      """

      assert check(code) == []
    end

    test "flags single letter parameters in def" do
      code = """
      defmodule BadNames do
        def compute(x, y), do: x + y
      end
      """

      issues = check(code)
      assert length(issues) == 2
      assert Enum.any?(issues, fn i -> i.message =~ "parameter `x`" end)
      assert Enum.any?(issues, fn i -> i.message =~ "parameter `y`" end)
    end

    test "flags single letter parameters in private defp" do
      code = """
      defmodule PrivateBad do
        defp helper(a), do: a
      end
      """

      issues = check(code)
      assert length(issues) == 1
      assert hd(issues).rule == :descriptive_names
    end

    test "ignores underscores" do
      code = """
      defmodule UnderscoreOk do
        def skip(_), do: :ok
        def skip_two(_, _), do: :ok
      end
      """

      assert check(code) == []
    end

    test "detects single letters inside pattern matches" do
      code = """
      defmodule PatternBad do
        def process({a, b}, [h | t]) do
          a + b + h
        end
      end
      """

      issues = check(code)
      # Should find a, b, h, t
      assert length(issues) == 4
    end

    test "detects single letters inside pattern matches inside anonymous functions" do
      code = """
      defmodule Transformer do
        def invert(map) do
          Enum.into(map, %{}, fn {k, v} -> {v, k} end)
        end
      end
      """

      issues = check(code)
      # Should find k, v
      assert length(issues) == 2
    end
  end
end
