defmodule Credence.Pattern.NoManualListReduceFixTest do
  use Credence.RuleCase, async: true

  alias Credence.Pattern.NoManualListReduce

  describe "collapse to Enum.reduce/3" do
    test "canonical arity-2 sum" do
      code = """
      defmodule Bad do
        def total(list) do
          sum(list, 0)
        end

        defp sum([], acc), do: acc
        defp sum([h | t], acc), do: sum(t, acc + h)
      end
      """

      expected = """
      defmodule Bad do
        def total(list) do
          sum(list, 0)
        end

        defp sum(list, acc) when is_list(list), do: Enum.reduce(list, acc, fn h, acc -> acc + h end)
      end
      """

      confirm_fix(fix(NoManualListReduce, code), expected)
    end

    test "arity-3 with a threaded-through parameter" do
      code = """
      defmodule Bad do
        defp scale([], _factor, acc), do: acc
        defp scale([h | t], factor, acc), do: scale(t, factor, acc + h * factor)
      end
      """

      expected = """
      defmodule Bad do
        defp scale(list, factor, acc) when is_list(list),
          do: Enum.reduce(list, acc, fn h, acc -> acc + h * factor end)
      end
      """

      confirm_fix(fix(NoManualListReduce, code), expected)
    end

    test "clauses in reversed order collapse at the first clause position" do
      code = """
      defmodule Bad do
        defp sum([h | t], acc), do: sum(t, acc + h)
        defp sum([], acc), do: acc
      end
      """

      expected = """
      defmodule Bad do
        defp sum(list, acc) when is_list(list), do: Enum.reduce(list, acc, fn h, acc -> acc + h end)
      end
      """

      confirm_fix(fix(NoManualListReduce, code), expected)
    end

    test "cons-building update" do
      code = """
      defmodule Bad do
        defp build([], acc), do: acc
        defp build([h | t], acc), do: build(t, [h | acc])
      end
      """

      expected = """
      defmodule Bad do
        defp build(list, acc) when is_list(list), do: Enum.reduce(list, acc, fn h, acc -> [h | acc] end)
      end
      """

      confirm_fix(fix(NoManualListReduce, code), expected)
    end
  end

  describe "idempotency and no-ops" do
    test "the collapsed output is left unchanged on a second pass" do
      code = """
      defmodule Bad do
        defp sum(list, acc) when is_list(list), do: Enum.reduce(list, acc, fn h, acc -> acc + h end)
      end
      """

      confirm_fix(fix(NoManualListReduce, code), code)
    end

    test "leaves an existing Enum.reduce/3 call untouched" do
      code = """
      defmodule Good do
        def sum(list), do: Enum.reduce(list, 0, fn h, acc -> acc + h end)
      end
      """

      confirm_fix(fix(NoManualListReduce, code), code)
    end

    test "leaves an update that reads the tail untouched" do
      code = """
      defmodule Good do
        defp f([], acc), do: acc
        defp f([h | t], acc), do: f(t, acc ++ [h | t])
      end
      """

      confirm_fix(fix(NoManualListReduce, code), code)
    end

    test "leaves a multi-statement recursive body untouched" do
      code = """
      defmodule Good do
        defp f([], acc), do: acc
        defp f([h | t], acc) do
          IO.inspect(h)
          f(t, acc + h)
        end
      end
      """

      confirm_fix(fix(NoManualListReduce, code), code)
    end
  end
end
