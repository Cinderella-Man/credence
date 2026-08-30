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
    test "leaves differing threaded-argument patterns untouched" do
      input = """
      defmodule CredenceFixtures.NoManualListReducePatternOriginal do
        def f([], :allowed, acc), do: acc
        def f([h | t], mode, acc), do: f(t, mode, acc + h)
      end
      """

      emitted = fix(NoManualListReduce, input)

      original_witness =
        input <>
          """

          try do
            CredenceFixtures.NoManualListReducePatternOriginal.f([], :rejected, 0)
            raise "original unexpectedly accepted :rejected"
          rescue
            FunctionClauseError -> :ok
          end
          """

      emitted_witness =
        emitted <>
          """

          try do
            CredenceFixtures.NoManualListReducePatternOriginal.f([], :rejected, 0)
            raise "emitted code unexpectedly accepted :rejected"
          rescue
            FunctionClauseError -> :ok
          end
          """

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(original_witness)
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted_witness)
      confirm_fix(emitted, input)
    end

    test "leaves clauses separated by an attribute assignment untouched" do
      input = """
      defmodule CredenceFixtures.NoManualListReduceAttributeOriginal do
        def f([], acc), do: acc
        @increment 2
        def f([h | t], acc), do: f(t, acc + h * @increment)
        def run, do: f([3], 0)
      end
      """

      emitted = fix(NoManualListReduce, input)

      original_witness =
        input <>
          """

          unless CredenceFixtures.NoManualListReduceAttributeOriginal.run() == 6,
            do: raise("original returned the wrong value")
          """

      emitted_witness =
        emitted <>
          """

          unless CredenceFixtures.NoManualListReduceAttributeOriginal.run() == 6,
            do: raise("emitted code changed the value")
          """

      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(original_witness)
      assert {:ok, []} = Credence.RuleHelpers.compile_and_capture(emitted_witness)
      confirm_fix(emitted, input)
    end

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
